package main

import (
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
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
		fmt.Fprintln(os.Stderr, "usage: fits-agent-host detect|start <claude|codex>")
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
	var selected *Tool
	for _, tool := range detectTools(strings.Split(os.Getenv("PATH"), string(os.PathListSeparator)), isExecutable) {
		if tool.ID == id {
			copy := tool
			selected = &copy
			break
		}
	}
	if selected == nil || selected.Status != "installed" {
		return fmt.Errorf("%s is not installed", id)
	}

	cmd := exec.Command(selected.Path)
	cmd.Stdin = os.Stdin
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	return cmd.Run()
}
