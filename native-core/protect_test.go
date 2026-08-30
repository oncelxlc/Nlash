package main

import (
	"encoding/binary"
	"encoding/json"
	"io"
	"net"
	"sync/atomic"
	"testing"
	"time"
)

func testProtectClient(t *testing.T, responder func(net.Conn)) *protectClient {
	t.Helper()
	return &protectClient{
		generation: "5e4f3ec5-37b9-4ed5-9b0e-d6746165f2c4",
		dial: func() (net.Conn, error) {
			client, server := net.Pipe()
			go func() {
				defer server.Close()
				responder(server)
			}()
			return client, nil
		},
	}
}

func writeProtectACK(t *testing.T, connection net.Conn, request protectRequest, ok bool, code string) {
	t.Helper()
	payload, err := json.Marshal(protectACK{
		Version: protectProtocolVersion, Type: "protectAck", RequestID: request.RequestID,
		Generation: request.Generation, OK: ok, ErrorCode: code,
	})
	if err != nil {
		t.Errorf("marshal acknowledgement: %v", err)
		return
	}
	header := make([]byte, 4)
	binary.BigEndian.PutUint32(header, uint32(len(payload)))
	if _, err = connection.Write(append(header, payload...)); err != nil {
		t.Errorf("write acknowledgement: %v", err)
	}
}

func readProtectRequest(t *testing.T, connection net.Conn) protectRequest {
	t.Helper()
	payload, err := readProtectFrame(connection)
	if err != nil {
		t.Errorf("read request: %v", err)
		return protectRequest{}
	}
	var request protectRequest
	if err = json.Unmarshal(payload, &request); err != nil {
		t.Errorf("decode request: %v", err)
	}
	return request
}

func TestProtectClientAcceptsMatchingACK(t *testing.T) {
	client := testProtectClient(t, func(connection net.Conn) {
		request := readProtectRequest(t, connection)
		writeProtectACK(t, connection, request, true, "")
	})
	if err := client.protect(42); err != nil {
		t.Fatalf("protect failed: %v", err)
	}
}

func TestProtectClientReusesConnection(t *testing.T) {
	var dialCount atomic.Int32
	client := &protectClient{
		generation: "5e4f3ec5-37b9-4ed5-9b0e-d6746165f2c4",
		dial: func() (net.Conn, error) {
			dialCount.Add(1)
			clientConnection, serverConnection := net.Pipe()
			go func() {
				defer serverConnection.Close()
				for index := 0; index < 2; index++ {
					request := readProtectRequest(t, serverConnection)
					writeProtectACK(t, serverConnection, request, true, "")
				}
			}()
			return clientConnection, nil
		},
	}
	defer client.close()

	if err := client.protect(42); err != nil {
		t.Fatalf("first protect failed: %v", err)
	}
	if err := client.protect(43); err != nil {
		t.Fatalf("second protect failed: %v", err)
	}
	if dialCount.Load() != 1 {
		t.Fatalf("unexpected protect connection count: %d", dialCount.Load())
	}
}

func TestProtectClientRejectsStaleGeneration(t *testing.T) {
	client := testProtectClient(t, func(connection net.Conn) {
		request := readProtectRequest(t, connection)
		request.Generation = "stale"
		writeProtectACK(t, connection, request, true, "")
	})
	if err := client.protect(42); err == nil {
		t.Fatal("expected stale generation error")
	}
}

func TestProtectClientReturnsStableRejection(t *testing.T) {
	client := testProtectClient(t, func(connection net.Conn) {
		request := readProtectRequest(t, connection)
		writeProtectACK(t, connection, request, false, "PROTECT_FAILED")
	})
	if err := client.protect(42); err == nil || err.Error() != "protect rejected: PROTECT_FAILED" {
		t.Fatalf("unexpected error: %v", err)
	}
}

func TestReadProtectFrameRejectsOversize(t *testing.T) {
	header := make([]byte, 4)
	binary.BigEndian.PutUint32(header, protectMaxPayload+1)
	if _, err := readProtectFrame(&shortReader{data: header}); err == nil {
		t.Fatal("expected oversized frame error")
	}
}

type shortReader struct {
	data []byte
}

func (reader *shortReader) Read(target []byte) (int, error) {
	if len(reader.data) == 0 {
		return 0, io.EOF
	}
	n := copy(target, reader.data)
	reader.data = reader.data[n:]
	return n, nil
}

func TestProtectClientTimeout(t *testing.T) {
	client := testProtectClient(t, func(connection net.Conn) {
		_, _ = readProtectFrame(connection)
		time.Sleep(100 * time.Millisecond)
	})
	client.timeout = 20 * time.Millisecond
	started := time.Now()
	if err := client.protect(42); err == nil {
		t.Fatal("expected timeout error")
	}
	if time.Since(started) >= 200*time.Millisecond {
		t.Fatal("protect request did not honor its deadline")
	}
}
