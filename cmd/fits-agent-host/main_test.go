package main

import "testing"

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
