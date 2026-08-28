package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"syscall"
)

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func address() string {
	return "127.0.0.1:" + envOr("TESTBED_PORT", "27025")
}

func password() string { return envOr("TESTBED_RCONPW", "testbed") }

func container() string { return envOr("TESTBED_CONTAINER", "mvmbots-testbed-srcds-1") }

// repoRoot is the working tree this binary was run from, found by the go.mod
// rather than by counting directories.
func repoRoot() (string, error) {
	dir, err := os.Getwd()
	if err != nil {
		return "", err
	}
	for {
		if _, err := os.Stat(filepath.Join(dir, "go.mod")); err == nil {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", errors.New("not inside the repository: no go.mod above here")
		}
		dir = parent
	}
}

func compile(ctx context.Context, root string) error {
	cmd := exec.CommandContext(ctx, "sh", filepath.Join(root, "testbed", "build.sh"))
	cmd.Dir = root
	out, err := cmd.CombinedOutput()
	if err != nil {
		return fmt.Errorf("the build failed:\n%s", tail(string(out), 20))
	}
	return nil
}

func tail(s string, lines int) string {
	all := strings.Split(strings.TrimRight(s, "\n"), "\n")
	if len(all) > lines {
		all = all[len(all)-lines:]
	}
	return strings.Join(all, "\n")
}

/*
hold takes the test-bed, and says who has it rather than waiting.

Two runners is not a slow run, it is two runs measuring each other's map
changes. That happened three times in one session before this existed, and each
time the results looked ordinary.
*/
func hold(path string) (func(), error) {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o644)
	if err != nil {
		return nil, err
	}
	if err := syscall.Flock(int(file.Fd()), syscall.LOCK_EX|syscall.LOCK_NB); err != nil {
		held, _ := os.ReadFile(path)
		file.Close()
		return nil, fmt.Errorf("the test-bed is already in use by %s", strings.TrimSpace(string(held)))
	}
	if err := file.Truncate(0); err == nil {
		fmt.Fprintf(file, "pid %d", os.Getpid())
	}
	return func() {
		_ = syscall.Flock(int(file.Fd()), syscall.LOCK_UN)
		file.Close()
		_ = os.Remove(path)
	}, nil
}
