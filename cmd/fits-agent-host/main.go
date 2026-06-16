package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"sync/atomic"
	"time"
	"unicode"

	"github.com/creack/pty"
)

type Tool struct {
	ID          string `json:"id"`
	DisplayName string `json:"displayName"`
	CommandName string `json:"commandName"`
	Status      string `json:"status"`
	Path        string `json:"path,omitempty"`
}

func main() {
	if len(os.Args) < 2 {
		fmt.Fprintln(os.Stderr, "usage: fits-agent-host detect|start <claude|codex>|run --task-dir <dir> <claude|codex> [args...]|pty --task-dir <dir> --cwd <dir> [--prompt-file <file>] [--done-sentinel <text>] [--done-file <file>] -- <command> [args...]")
		os.Exit(2)
	}

	switch os.Args[1] {
	case "detect":
		if err := json.NewEncoder(os.Stdout).Encode(detectTools(strings.Split(os.Getenv("PATH"), string(os.PathListSeparator)), isExecutable)); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	case "start":
		if len(os.Args) < 3 {
			fmt.Fprintln(os.Stderr, "usage: fits-agent-host start <claude|codex>")
			os.Exit(2)
		}
		if err := startTool(os.Args[2]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	case "run":
		if err := runTool(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	case "pty":
		if err := ptyTool(os.Args[2:]); err != nil {
			fmt.Fprintln(os.Stderr, err)
			os.Exit(1)
		}
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n", os.Args[1])
		os.Exit(2)
	}
}

func detectTools(pathEntries []string, exists func(string) bool) []Tool {
	return []Tool{
		detectTool("claude", "Claude Code", "claude", pathEntries, []string{
			"/Applications/Claude.app/Contents/MacOS/Claude",
			"/Applications/Claude Code.app/Contents/MacOS/Claude Code",
		}, exists),
		detectTool("codex", "Codex", "codex", pathEntries, []string{
			"/Applications/Codex.app/Contents/Resources/codex",
			"/Applications/Codex.app/Contents/MacOS/Codex",
		}, exists),
	}
}

func detectTool(id, displayName, commandName string, pathEntries []string, knownPaths []string, exists func(string) bool) Tool {
	for _, entry := range pathEntries {
		if entry == "" {
			continue
		}
		path := filepath.Join(entry, commandName)
		if exists(path) {
			return Tool{ID: id, DisplayName: displayName, CommandName: commandName, Status: "installed", Path: path}
		}
	}
	for _, path := range knownPaths {
		if exists(path) {
			return Tool{ID: id, DisplayName: displayName, CommandName: commandName, Status: "installed", Path: path}
		}
	}
	return Tool{ID: id, DisplayName: displayName, CommandName: commandName, Status: "missing"}
}

func isExecutable(path string) bool {
	info, err := os.Stat(path)
	if err != nil || info.IsDir() {
		return false
	}
	return info.Mode()&0111 != 0
}

func startTool(id string) error {
	selected, err := findTool(id)
	if err != nil {
		return err
	}

	return runCommand(selected.Path, nil, "", os.Stdin, os.Stdout, os.Stderr)
}

func runTool(args []string) error {
	if len(args) < 3 || args[0] != "--task-dir" || strings.TrimSpace(args[1]) == "" {
		return fmt.Errorf("usage: fits-agent-host run --task-dir <dir> <claude|codex> [args...]")
	}

	taskDir := args[1]
	id := args[2]
	selected, err := findTool(id)
	if err != nil {
		return err
	}

	return runCommand(selected.Path, args[3:], taskDir, os.Stdin, os.Stdout, os.Stderr)
}

func ptyTool(args []string) error {
	taskDir := ""
	cwd := ""
	promptFile := ""
	promptDelayMS := 750
	doneSentinel := ""
	doneFile := ""
	requireSentinel := false
	autoQuitCommand := "/quit\r"

	for len(args) > 0 {
		if args[0] == "--" {
			args = args[1:]
			break
		}
		if args[0] == "--require-sentinel" {
			requireSentinel = true
			args = args[1:]
			continue
		}
		if len(args) < 2 {
			return fmt.Errorf("usage: fits-agent-host pty --task-dir <dir> --cwd <dir> [--prompt-file <file>] [--prompt-delay-ms <ms>] [--done-sentinel <text>] [--done-file <file>] [--require-sentinel] -- <command> [args...]")
		}
		switch args[0] {
		case "--task-dir":
			taskDir = args[1]
		case "--cwd":
			cwd = args[1]
		case "--prompt-file":
			promptFile = args[1]
		case "--done-sentinel":
			doneSentinel = args[1]
		case "--done-file":
			doneFile = args[1]
		case "--auto-quit-command":
			autoQuitCommand = args[1]
		case "--prompt-delay-ms":
			value, err := strconv.Atoi(args[1])
			if err != nil || value < 0 {
				return fmt.Errorf("invalid --prompt-delay-ms: %s", args[1])
			}
			promptDelayMS = value
		default:
			return fmt.Errorf("unknown pty option: %s", args[0])
		}
		args = args[2:]
	}

	if strings.TrimSpace(taskDir) == "" || strings.TrimSpace(cwd) == "" || len(args) == 0 {
		return fmt.Errorf("usage: fits-agent-host pty --task-dir <dir> --cwd <dir> [--prompt-file <file>] [--prompt-delay-ms <ms>] [--done-sentinel <text>] [--done-file <file>] [--require-sentinel] -- <command> [args...]")
	}

	commandPath, err := resolveCommandPath(args[0])
	if err != nil {
		return err
	}
	return runPTYCommand(commandPath, args[1:], taskDir, cwd, promptFile, promptDelayMS, doneSentinel, requireSentinel, autoQuitCommand, doneFile, os.Stdin, os.Stdout)
}

func findTool(id string) (*Tool, error) {
	var selected *Tool
	for _, tool := range detectTools(strings.Split(os.Getenv("PATH"), string(os.PathListSeparator)), isExecutable) {
		if tool.ID == id {
			copy := tool
			selected = &copy
			break
		}
	}
	if selected == nil || selected.Status != "installed" {
		return nil, fmt.Errorf("%s is not installed", id)
	}
	return selected, nil
}

func resolveCommandPath(command string) (string, error) {
	cleanCommand := strings.TrimSpace(command)
	if cleanCommand == "" {
		return "", fmt.Errorf("missing command")
	}

	if tool, err := findTool(cleanCommand); err == nil {
		return tool.Path, nil
	}
	if strings.Contains(cleanCommand, string(os.PathSeparator)) {
		if isExecutable(cleanCommand) {
			return cleanCommand, nil
		}
		return "", fmt.Errorf("%s is not executable", cleanCommand)
	}
	path, err := exec.LookPath(cleanCommand)
	if err != nil {
		return "", fmt.Errorf("%s is not installed", cleanCommand)
	}
	return path, nil
}

func runCommand(commandPath string, args []string, taskDir string, stdin io.Reader, stdout io.Writer, stderr io.Writer) error {
	cmd := exec.Command(commandPath, args...)

	if strings.TrimSpace(taskDir) == "" {
		cmd.Stdin = stdin
		cmd.Stdout = stdout
		cmd.Stderr = stderr
		return cmd.Run()
	}

	if err := os.MkdirAll(taskDir, 0o755); err != nil {
		return err
	}
	logFile, err := os.OpenFile(filepath.Join(taskDir, "terminal.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	defer logFile.Close()

	cmd.Stdout = io.MultiWriter(stdout, logFile)
	cmd.Stderr = io.MultiWriter(stderr, logFile)
	return cmd.Run()
}

func runPTYCommand(commandPath string, args []string, taskDir string, cwd string, promptFile string, promptDelayMS int, doneSentinel string, requireSentinel bool, autoQuitCommand string, doneFile string, stdin io.Reader, stdout io.Writer) error {
	if err := os.MkdirAll(taskDir, 0o755); err != nil {
		return err
	}
	if strings.TrimSpace(doneFile) != "" {
		_ = os.Remove(doneFile)
	}
	logFile, err := os.OpenFile(filepath.Join(taskDir, "terminal.log"), os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0o644)
	if err != nil {
		return err
	}
	defer logFile.Close()

	var prompt []byte
	if strings.TrimSpace(promptFile) != "" {
		prompt, err = os.ReadFile(promptFile)
		if err != nil {
			return err
		}
		promptText := strings.TrimRight(string(prompt), "\r\n") + "\r"
		prompt = []byte(promptText)
	}

	cmd := exec.Command(commandPath, args...)
	cmd.Dir = cwd
	cmd.Env = terminalEnvironment(os.Environ())
	ptmx, err := pty.Start(cmd)
	if err != nil {
		return err
	}

	copyDone := make(chan error, 1)
	var completionObserved atomic.Bool
	outputSentinel := doneSentinel
	if strings.TrimSpace(doneFile) != "" {
		outputSentinel = ""
	}
	go func() {
		copyDone <- copyPTYOutput(ptmx, io.MultiWriter(stdout, logFile), outputSentinel, &completionObserved)
	}()
	processDone := make(chan struct{})
	if strings.TrimSpace(doneSentinel) != "" || strings.TrimSpace(doneFile) != "" {
		go watchCompletionAndStopProcess(cmd, ptmx, processDone, doneFile, doneSentinel, autoQuitCommand, &completionObserved)
	}

	if stdin != nil {
		go func() {
			_, _ = io.Copy(ptmx, stdin)
		}()
	}

	if len(prompt) > 0 {
		go func() {
			time.Sleep(time.Duration(promptDelayMS) * time.Millisecond)
			_, _ = ptmx.Write(prompt)
		}()
	}

	waitErr := cmd.Wait()
	close(processDone)
	_ = ptmx.Close()
	copyErr := <-copyDone
	if copyErr != nil && copyErr != io.EOF && !strings.Contains(copyErr.Error(), "input/output error") && !strings.Contains(copyErr.Error(), "file already closed") {
		return copyErr
	}
	if !completionObserved.Load() && strings.TrimSpace(doneFile) != "" && doneFileContainsSentinel(doneFile, doneSentinel) {
		completionObserved.Store(true)
	}
	if waitErr != nil && !completionObserved.Load() {
		return waitErr
	}
	if requireSentinel && !completionObserved.Load() {
		return fmt.Errorf("done sentinel was not observed: %s", doneSentinel)
	}
	return nil
}

func copyPTYOutput(ptmx io.ReadWriter, output io.Writer, doneSentinel string, completionObserved *atomic.Bool) error {
	buffer := make([]byte, 4096)
	var visibleBuffer strings.Builder
	normalizedSentinel := normalizeSentinel(doneSentinel)

	for {
		n, err := ptmx.Read(buffer)
		if n > 0 {
			chunk := buffer[:n]
			if _, writeErr := output.Write(chunk); writeErr != nil {
				return writeErr
			}
			if normalizedSentinel != "" && !completionObserved.Load() {
				visibleBuffer.WriteString(stripTerminalControls(string(chunk)))
				if visibleBuffer.Len() > 20000 {
					text := visibleBuffer.String()
					visibleBuffer.Reset()
					visibleBuffer.WriteString(text[len(text)-10000:])
				}
				if strings.Contains(normalizeSentinel(visibleBuffer.String()), normalizedSentinel) {
					completionObserved.Store(true)
				}
			}
		}
		if err != nil {
			return err
		}
	}
}

func watchCompletionAndStopProcess(cmd *exec.Cmd, ptmx io.Writer, processDone <-chan struct{}, doneFile string, doneSentinel string, autoQuitCommand string, completionObserved *atomic.Bool) {
	ticker := time.NewTicker(100 * time.Millisecond)
	defer ticker.Stop()

	for {
		select {
		case <-processDone:
			return
		case <-ticker.C:
			if !completionObserved.Load() && strings.TrimSpace(doneFile) != "" && doneFileContainsSentinel(doneFile, doneSentinel) {
				completionObserved.Store(true)
			}
			if completionObserved.Load() {
				time.Sleep(700 * time.Millisecond)
				if autoQuitCommand != "" {
					_, _ = ptmx.Write([]byte(autoQuitCommand))
				}
				time.Sleep(1200 * time.Millisecond)
				if cmd.Process != nil {
					_ = cmd.Process.Signal(os.Interrupt)
				}
				time.Sleep(1200 * time.Millisecond)
				if cmd.Process != nil {
					_ = cmd.Process.Kill()
				}
				return
			}
		}
	}
}

func doneFileContainsSentinel(path string, doneSentinel string) bool {
	data, err := os.ReadFile(path)
	if err != nil {
		return false
	}
	if strings.TrimSpace(doneSentinel) == "" {
		return len(strings.TrimSpace(string(data))) > 0
	}
	return strings.Contains(string(data), doneSentinel)
}

func terminalEnvironment(base []string) []string {
	env := make([]string, 0, len(base)+2)
	for _, item := range base {
		if strings.HasPrefix(item, "TERM=") || strings.HasPrefix(item, "COLORTERM=") {
			continue
		}
		env = append(env, item)
	}
	env = append(env, "TERM=xterm-256color", "COLORTERM=truecolor")
	return env
}

var terminalControlPatterns = []*regexp.Regexp{
	regexp.MustCompile(`\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)`),
	regexp.MustCompile(`\x1b\[[0-?]*[ -/]*[@-~]`),
	regexp.MustCompile(`\x1b[()][A-Za-z0-9]`),
	regexp.MustCompile(`\x1b[=><][0-9;]*[A-Za-z]?`),
	regexp.MustCompile(`\x1b[78]`),
}

func stripTerminalControls(text string) string {
	output := text
	for _, pattern := range terminalControlPatterns {
		output = pattern.ReplaceAllString(output, "")
	}
	return output
}

func normalizeSentinel(text string) string {
	var builder strings.Builder
	for _, r := range stripTerminalControls(text) {
		if !unicode.IsSpace(r) && !unicode.IsControl(r) {
			builder.WriteRune(r)
		}
	}
	return builder.String()
}
