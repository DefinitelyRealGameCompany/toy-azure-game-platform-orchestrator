package main

import (
	"bufio"
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"os/exec"
	"sync"
)

//go:embed static/*
var staticFiles embed.FS

// Required environment variables
var requiredEnvVars = []string{
	"TF_VAR_github_org",
	"TF_VAR_github_pat",
	"TF_VAR_source_owner",
	"ARM_SUBSCRIPTION_ID",
	"TF_VAR_subscription_id",
}

// LaunchRequest represents the request to launch a new game
type LaunchRequest struct {
	GamePrefix string `json:"game_prefix,omitempty"`
}

// LaunchResponse represents the response from launching a game
type LaunchResponse struct {
	Success bool   `json:"success"`
	Message string `json:"message"`
	Output  string `json:"output,omitempty"`
}

// EnvStatus represents the status of required environment variables
type EnvStatus struct {
	Variable string `json:"variable"`
	IsSet    bool   `json:"is_set"`
}

// Process state tracking
var (
	processRunning bool
	processMutex   sync.Mutex
)

func main() {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	// Check environment variables at startup
	missingVars := checkEnvVars()
	if len(missingVars) > 0 {
		log.Printf("Warning: Missing environment variables: %v", missingVars)
		log.Println("The server will start, but launching games will fail until these are set.")
	}

	// Setup routes
	http.HandleFunc("/", serveIndex)
	http.HandleFunc("/api/launch", handleLaunch)
	http.HandleFunc("/api/launch-stream", handleLaunchStream)
	http.HandleFunc("/api/env-status", handleEnvStatus)

	log.Printf("Starting server on port %s...", port)
	log.Printf("Open http://localhost:%s in your browser", port)

	if err := http.ListenAndServe(":"+port, nil); err != nil {
		log.Fatalf("Failed to start server: %v", err)
	}
}

func checkEnvVars() []string {
	var missing []string
	for _, v := range requiredEnvVars {
		if os.Getenv(v) == "" {
			missing = append(missing, v)
		}
	}
	return missing
}

func serveIndex(w http.ResponseWriter, r *http.Request) {
	if r.URL.Path != "/" {
		http.NotFound(w, r)
		return
	}

	content, err := staticFiles.ReadFile("static/index.html")
	if err != nil {
		http.Error(w, "Failed to load page", http.StatusInternalServerError)
		return
	}

	w.Header().Set("Content-Type", "text/html")
	w.Write(content)
}

func handleEnvStatus(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodGet {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	var statuses []EnvStatus
	for _, v := range requiredEnvVars {
		statuses = append(statuses, EnvStatus{
			Variable: v,
			IsSet:    os.Getenv(v) != "",
		})
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(statuses)
}

func handleLaunch(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Check if a process is already running
	processMutex.Lock()
	if processRunning {
		processMutex.Unlock()
		sendJSON(w, http.StatusConflict, LaunchResponse{
			Success: false,
			Message: "A game launch is already in progress. Please wait for it to complete.",
		})
		return
	}
	processRunning = true
	processMutex.Unlock()

	defer func() {
		processMutex.Lock()
		processRunning = false
		processMutex.Unlock()
	}()

	// Check environment variables
	missingVars := checkEnvVars()
	if len(missingVars) > 0 {
		sendJSON(w, http.StatusBadRequest, LaunchResponse{
			Success: false,
			Message: fmt.Sprintf("Missing required environment variables: %v", missingVars),
		})
		return
	}

	// Parse request
	var req LaunchRequest
	if r.Body != nil {
		defer r.Body.Close()
		json.NewDecoder(r.Body).Decode(&req)
	}

	// Build command
	scriptPath := "../launchers/new_game.sh"
	var cmd *exec.Cmd
	if req.GamePrefix != "" {
		cmd = exec.Command("bash", scriptPath, req.GamePrefix)
	} else {
		cmd = exec.Command("bash", scriptPath)
	}

	// Set working directory to webserver directory
	cmd.Dir = "."

	// Set AUTO_START_NEW_GAME to bypass interactive confirmation
	cmd.Env = append(os.Environ(), "AUTO_START_NEW_GAME=true")

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		sendJSON(w, http.StatusInternalServerError, LaunchResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to create stdout pipe: %v", err),
		})
		return
	}

	stderr, err := cmd.StderrPipe()
	if err != nil {
		sendJSON(w, http.StatusInternalServerError, LaunchResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to create stderr pipe: %v", err),
		})
		return
	}

	// Start the command
	if err := cmd.Start(); err != nil {
		sendJSON(w, http.StatusInternalServerError, LaunchResponse{
			Success: false,
			Message: fmt.Sprintf("Failed to start script: %v", err),
		})
		return
	}

	// Collect output from stdout and stderr
	var output string
	stdoutOutput, _ := io.ReadAll(stdout)
	stderrOutput, _ := io.ReadAll(stderr)
	output = string(stdoutOutput) + string(stderrOutput)

	// Wait for command to complete
	err = cmd.Wait()
	if err != nil {
		sendJSON(w, http.StatusInternalServerError, LaunchResponse{
			Success: false,
			Message: fmt.Sprintf("Script execution failed: %v", err),
			Output:  output,
		})
		return
	}

	sendJSON(w, http.StatusOK, LaunchResponse{
		Success: true,
		Message: "Game launch completed successfully",
		Output:  output,
	})
}

func sendJSON(w http.ResponseWriter, status int, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(data)
}

// handleLaunchStream handles launching a new game with Server-Sent Events streaming
func handleLaunchStream(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Check if a process is already running
	processMutex.Lock()
	if processRunning {
		processMutex.Unlock()
		http.Error(w, "A game launch is already in progress", http.StatusConflict)
		return
	}
	processRunning = true
	processMutex.Unlock()

	defer func() {
		processMutex.Lock()
		processRunning = false
		processMutex.Unlock()
	}()

	// Check environment variables
	missingVars := checkEnvVars()
	if len(missingVars) > 0 {
		http.Error(w, fmt.Sprintf("Missing required environment variables: %v", missingVars), http.StatusBadRequest)
		return
	}

	// Parse request
	var req LaunchRequest
	if r.Body != nil {
		defer r.Body.Close()
		json.NewDecoder(r.Body).Decode(&req)
	}

	// Set up SSE headers
	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("X-Accel-Buffering", "no")

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "Streaming not supported", http.StatusInternalServerError)
		return
	}

	// Build command
	scriptPath := "../launchers/new_game.sh"
	var cmd *exec.Cmd
	if req.GamePrefix != "" {
		cmd = exec.Command("bash", scriptPath, req.GamePrefix)
	} else {
		cmd = exec.Command("bash", scriptPath)
	}

	// Set working directory to webserver directory
	cmd.Dir = "."

	// Set AUTO_START_NEW_GAME to bypass interactive confirmation
	cmd.Env = append(os.Environ(), "AUTO_START_NEW_GAME=true")

	stdout, err := cmd.StdoutPipe()
	if err != nil {
		fmt.Fprintf(w, "event: error\ndata: Failed to create stdout pipe: %v\n\n", err)
		flusher.Flush()
		return
	}

	stderr, err := cmd.StderrPipe()
	if err != nil {
		fmt.Fprintf(w, "event: error\ndata: Failed to create stderr pipe: %v\n\n", err)
		flusher.Flush()
		return
	}

	// Start the command
	if err := cmd.Start(); err != nil {
		fmt.Fprintf(w, "event: error\ndata: Failed to start script: %v\n\n", err)
		flusher.Flush()
		return
	}

	// Send initial message
	fmt.Fprintf(w, "event: start\ndata: Script started\n\n")
	flusher.Flush()

	// Create a channel to signal when reading is done
	done := make(chan struct{})
	var wg sync.WaitGroup

	// Stream output function
	streamOutput := func(scanner *bufio.Scanner, prefix string) {
		defer wg.Done()
		for scanner.Scan() {
			line := scanner.Text()
			// Escape newlines in the data for SSE format
			fmt.Fprintf(w, "event: output\ndata: %s%s\n\n", prefix, line)
			flusher.Flush()
		}
	}

	wg.Add(2)
	go streamOutput(bufio.NewScanner(stdout), "")
	go streamOutput(bufio.NewScanner(stderr), "[stderr] ")

	// Wait for output reading to complete in a goroutine
	go func() {
		wg.Wait()
		close(done)
	}()

	// Wait for the command to complete
	<-done
	err = cmd.Wait()

	if err != nil {
		fmt.Fprintf(w, "event: error\ndata: Script execution failed: %v\n\n", err)
	} else {
		fmt.Fprintf(w, "event: complete\ndata: Script completed successfully\n\n")
	}
	flusher.Flush()
}
