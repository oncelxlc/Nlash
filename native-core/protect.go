package main

import (
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"time"
)

const (
	protectProtocolVersion = 1
	protectMaxPayload      = 4096
	protectACKTimeout      = 3 * time.Second
)

type protectRequest struct {
	Version    int    `json:"version"`
	Type       string `json:"type"`
	RequestID  uint64 `json:"requestId"`
	Generation string `json:"generation"`
	FD         int    `json:"fd"`
}

type protectACK struct {
	Version    int    `json:"version"`
	Type       string `json:"type"`
	RequestID  uint64 `json:"requestId"`
	Generation string `json:"generation"`
	OK         bool   `json:"ok"`
	ErrorCode  string `json:"errorCode,omitempty"`
	Message    string `json:"message,omitempty"`
}

type protectDialFunc func() (net.Conn, error)

type protectClient struct {
	generation string
	dial       protectDialFunc
	timeout    time.Duration
	nextID     atomic.Uint64
	mu         sync.Mutex
	connection net.Conn
}

type protectTransportError struct {
	operation string
	err       error
}

func (failure *protectTransportError) Error() string {
	return fmt.Sprintf("%s: %v", failure.operation, failure.err)
}

func newProtectClient(socketPath string, generation string) (*protectClient, error) {
	if socketPath == "" || generation == "" {
		return nil, errors.New("protect channel options are incomplete")
	}
	return &protectClient{
		generation: generation,
		timeout:    protectACKTimeout,
		dial: func() (net.Conn, error) {
			return net.DialTimeout("unix", socketPath, protectACKTimeout)
		},
	}, nil
}

func (client *protectClient) protect(fd int) error {
	if fd < 0 {
		return errors.New("invalid outbound socket")
	}
	client.mu.Lock()
	defer client.mu.Unlock()

	var lastError error
	for attempt := 0; attempt < 2; attempt++ {
		lastError = client.protectLocked(fd)
		if lastError == nil {
			return nil
		}
		if _, retryable := lastError.(*protectTransportError); !retryable {
			return lastError
		}
		client.closeLocked()
	}
	return lastError
}

func (client *protectClient) protectLocked(fd int) error {
	requestID := client.nextID.Add(1)
	request := protectRequest{
		Version:    protectProtocolVersion,
		Type:       "protectRequest",
		RequestID:  requestID,
		Generation: client.generation,
		FD:         fd,
	}
	payload, err := json.Marshal(request)
	if err != nil {
		return fmt.Errorf("encode protect request: %w", err)
	}
	if len(payload) > protectMaxPayload {
		return errors.New("protect request is too large")
	}

	connection := client.connection
	if connection == nil {
		connection, err = client.dial()
		if err != nil {
			return &protectTransportError{operation: "connect protect channel", err: err}
		}
		client.connection = connection
	}
	timeout := client.timeout
	if timeout <= 0 {
		timeout = protectACKTimeout
	}
	if err = connection.SetDeadline(time.Now().Add(timeout)); err != nil {
		return &protectTransportError{operation: "set protect deadline", err: err}
	}

	frame := make([]byte, 4+len(payload))
	binary.BigEndian.PutUint32(frame[:4], uint32(len(payload)))
	copy(frame[4:], payload)
	if _, err = connection.Write(frame); err != nil {
		return &protectTransportError{operation: "send protect request", err: err}
	}

	responsePayload, err := readProtectFrame(connection)
	if err != nil {
		return &protectTransportError{operation: "read protect acknowledgement", err: err}
	}
	var response protectACK
	if err = json.Unmarshal(responsePayload, &response); err != nil {
		return errors.New("invalid protect acknowledgement")
	}
	if response.Version != protectProtocolVersion || response.Type != "protectAck" ||
		response.RequestID != requestID || response.Generation != client.generation {
		return errors.New("mismatched protect acknowledgement")
	}
	if !response.OK {
		if response.ErrorCode == "" {
			response.ErrorCode = "PROTECT_REJECTED"
		}
		return fmt.Errorf("protect rejected: %s", response.ErrorCode)
	}
	return nil
}

func (client *protectClient) close() {
	client.mu.Lock()
	defer client.mu.Unlock()
	client.closeLocked()
}

func (client *protectClient) closeLocked() {
	connection := client.connection
	client.connection = nil
	if connection != nil {
		_ = connection.Close()
	}
}

func readProtectFrame(reader io.Reader) ([]byte, error) {
	header := make([]byte, 4)
	if _, err := io.ReadFull(reader, header); err != nil {
		return nil, err
	}
	size := binary.BigEndian.Uint32(header)
	if size == 0 || size > protectMaxPayload {
		return nil, errors.New("invalid protect frame length")
	}
	payload := make([]byte, int(size))
	if _, err := io.ReadFull(reader, payload); err != nil {
		return nil, err
	}
	return payload, nil
}
