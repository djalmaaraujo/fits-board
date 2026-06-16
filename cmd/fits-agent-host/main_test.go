package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDetectToolsFindsPathAndAppTools(t *testing.T) {
	tools := detectTools(
		[]string{"/usr/bin", "/Users/cooper/.local/bin"},
		func(path string) bool {
			return path == "/Users/cooper/.local/bin/claude" ||
				path == "/Applications/Codex.app/Contents/Resources/codex"
		},
	)

	if tools[0].ID != "claude" || tools[0].Status != "installed" {
		t.Fatalf("expected claude installed, got %#v", tools[0])
	}
	if tools[1].ID != "codex" || tools[1].Status != "installed" {
		t.Fatalf("expected codex installed, got %#v", tools[1])
	}
}

func TestDetectToolsReportsMissing(t *testing.T) {
	tools := detectTools([]string{"/usr/bin"}, func(string) bool { return false })

	for _, tool := range tools {
		if tool.Status != "missing" {
			t.Fatalf("expected %s missing, got %#v", tool.ID, tool)
		}
	}
}

func TestRunCommandMirrorsStdoutAndStderrToTaskTerminalLog(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "agent.sh")
	if err := os.WriteFile(script, []byte("#!/bin/sh\necho planning\necho warning >&2\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	taskDir := filepath.Join(dir, "task")
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	if err := runCommand(script, nil, taskDir, strings.NewReader(""), &stdout, &stderr); err != nil {
		t.Fatal(err)
	}

	if stdout.String() != "planning\n" {
		t.Fatalf("unexpected stdout: %q", stdout.String())
	}
	if stderr.String() != "warning\n" {
		t.Fatalf("unexpected stderr: %q", stderr.String())
	}
	log, err := os.ReadFile(filepath.Join(taskDir, "terminal.log"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(log), "planning") || !strings.Contains(string(log), "warning") {
		t.Fatalf("terminal.log did not mirror both streams: %q", string(log))
	}
}

func TestRunCommandDoesNotForwardStdinForTaskRuns(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "agent.sh")
	if err := os.WriteFile(script, []byte("#!/bin/sh\nif read line; then echo stdin:$line; else echo no-stdin; fi\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	taskDir := filepath.Join(dir, "task")
	var stdout bytes.Buffer
	var stderr bytes.Buffer

	if err := runCommand(script, nil, taskDir, strings.NewReader("unexpected\n"), &stdout, &stderr); err != nil {
		t.Fatal(err)
	}

	if stdout.String() != "no-stdin\n" {
		t.Fatalf("task run should not receive stdin, got stdout %q", stdout.String())
	}
}

func TestRunPTYCommandProvidesTTYAndTypesPrompt(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "agent.sh")
	if err := os.WriteFile(script, []byte("#!/bin/sh\nif [ -t 0 ]; then echo tty-ok; else echo no-tty; fi\nprintf 'prompt> '\nIFS= read -r line\necho typed:$line\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	taskDir := filepath.Join(dir, "task")
	promptFile := filepath.Join(dir, "prompt.md")
	if err := os.WriteFile(promptFile, []byte("hello from fits\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	var stdout bytes.Buffer

	if err := runPTYCommand(script, nil, taskDir, dir, promptFile, 0, "", false, "/quit\r", "", nil, &stdout); err != nil {
		t.Fatal(err)
	}

	output := stdout.String()
	if !strings.Contains(output, "tty-ok") {
		t.Fatalf("expected PTY-backed process, got output %q", output)
	}
	if !strings.Contains(output, "typed:hello from fits") {
		t.Fatalf("expected typed prompt, got output %q", output)
	}
	log, err := os.ReadFile(filepath.Join(taskDir, "terminal.log"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(log), "tty-ok") || !strings.Contains(string(log), "typed:hello from fits") {
		t.Fatalf("terminal.log did not mirror PTY output: %q", string(log))
	}
}

func TestRunPTYCommandProvidesUsableTerminalEnvironment(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "agent.sh")
	if err := os.WriteFile(script, []byte("#!/bin/sh\necho TERM=$TERM\necho COLORTERM=$COLORTERM\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	taskDir := filepath.Join(dir, "task")
	var stdout bytes.Buffer

	if err := runPTYCommand(script, nil, taskDir, dir, "", 0, "", false, "/quit\r", "", nil, &stdout); err != nil {
		t.Fatal(err)
	}

	output := stdout.String()
	if !strings.Contains(output, "TERM=xterm-256color") {
		t.Fatalf("expected usable TERM, got output %q", output)
	}
	if !strings.Contains(output, "COLORTERM=truecolor") {
		t.Fatalf("expected truecolor terminal, got output %q", output)
	}
}

func TestRunPTYCommandQuitsAfterDoneSentinel(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "agent.sh")
	if err := os.WriteFile(script, []byte("#!/bin/sh\nprintf 'ready> '\nIFS= read -r line\necho received:$line\necho FITS_DONE_123\nIFS= read -r command\necho command:$command\n[ \"$command\" = \"/quit\" ]\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	taskDir := filepath.Join(dir, "task")
	promptFile := filepath.Join(dir, "prompt.md")
	if err := os.WriteFile(promptFile, []byte("do the work\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	var stdout bytes.Buffer

	if err := runPTYCommand(script, nil, taskDir, dir, promptFile, 0, "FITS_DONE_123", true, "/quit\r", "", nil, &stdout); err != nil {
		t.Fatal(err)
	}

	output := stdout.String()
	if !strings.Contains(output, "received:do the work") {
		t.Fatalf("expected typed prompt, got output %q", output)
	}
	if !strings.Contains(output, "command:/quit") {
		t.Fatalf("expected sentinel to trigger quit command, got output %q", output)
	}
}

func TestRunPTYCommandQuitsAfterDoneFile(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "agent.sh")
	if err := os.WriteFile(script, []byte("#!/bin/sh\ndone_file=$1\nprintf 'ready> '\nIFS= read -r line\necho received:$line\nprintf 'FITS_DONE_456\\n' > \"$done_file\"\nwhile true; do sleep 1; done\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	taskDir := filepath.Join(dir, "task")
	promptFile := filepath.Join(dir, "prompt.md")
	doneFile := filepath.Join(taskDir, "stage-done.txt")
	if err := os.WriteFile(promptFile, []byte("finish from fits\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	var stdout bytes.Buffer

	if err := runPTYCommand(script, []string{doneFile}, taskDir, dir, promptFile, 0, "FITS_DONE_456", true, "/quit\r", doneFile, nil, &stdout); err != nil {
		t.Fatal(err)
	}

	output := stdout.String()
	if !strings.Contains(output, "received:finish from fits") {
		t.Fatalf("expected typed prompt, got output %q", output)
	}
	doneText, err := os.ReadFile(doneFile)
	if err != nil {
		t.Fatal(err)
	}
	if strings.TrimSpace(string(doneText)) != "FITS_DONE_456" {
		t.Fatalf("unexpected done file: %q", string(doneText))
	}
}

func TestRunPTYCommandRequiresDoneFileWhenConfigured(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "agent.sh")
	if err := os.WriteFile(script, []byte("#!/bin/sh\nprintf 'ready> '\nIFS= read -r line\necho received:$line\necho FITS_DONE_789\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	taskDir := filepath.Join(dir, "task")
	promptFile := filepath.Join(dir, "prompt.md")
	doneFile := filepath.Join(taskDir, "stage-done.txt")
	if err := os.WriteFile(promptFile, []byte("finish from fits\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	var stdout bytes.Buffer

	err := runPTYCommand(script, nil, taskDir, dir, promptFile, 0, "FITS_DONE_789", true, "/quit\r", doneFile, nil, &stdout)
	if err == nil {
		t.Fatalf("expected missing done file to fail, got output %q", stdout.String())
	}
	if !strings.Contains(err.Error(), "done sentinel was not observed") {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestRunPTYCommandAcceptsDoneFileWrittenBeforeFastExit(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(dir, "agent.sh")
	if err := os.WriteFile(script, []byte("#!/bin/sh\ndone_file=$1\nprintf 'ready> '\nIFS= read -r line\necho received:$line\nprintf 'FITS_DONE_FAST\\n' > \"$done_file\"\nexit 0\n"), 0o755); err != nil {
		t.Fatal(err)
	}
	taskDir := filepath.Join(dir, "task")
	promptFile := filepath.Join(dir, "prompt.md")
	doneFile := filepath.Join(taskDir, "stage-done.txt")
	if err := os.WriteFile(promptFile, []byte("finish from fits\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	var stdout bytes.Buffer

	if err := runPTYCommand(script, []string{doneFile}, taskDir, dir, promptFile, 0, "FITS_DONE_FAST", true, "/quit\r", doneFile, nil, &stdout); err != nil {
		t.Fatal(err)
	}
}
