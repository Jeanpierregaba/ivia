package auth

import (
	"bufio"
	"context"
	"io"
	"log/slog"
	"net"
	"strings"
	"testing"
)

// fakeSMTP est un serveur SMTP minimal qui enregistre le message reçu.
func fakeSMTP(t *testing.T) (addr string, received chan string) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	received = make(chan string, 1)
	go func() {
		conn, err := ln.Accept()
		if err != nil {
			return
		}
		defer conn.Close()
		defer ln.Close()
		r := bufio.NewReader(conn)
		write := func(s string) { _, _ = io.WriteString(conn, s+"\r\n") }
		write("220 fake")
		var data strings.Builder
		inData := false
		for {
			line, err := r.ReadString('\n')
			if err != nil {
				return
			}
			if inData {
				if line == ".\r\n" {
					inData = false
					received <- data.String()
					write("250 ok")
					continue
				}
				data.WriteString(line)
				continue
			}
			switch cmd := strings.ToUpper(strings.TrimSpace(line)); {
			case strings.HasPrefix(cmd, "EHLO"), strings.HasPrefix(cmd, "HELO"):
				write("250 fake")
			case cmd == "DATA":
				inData = true
				write("354 go")
			case cmd == "QUIT":
				write("221 bye")
				return
			default:
				write("250 ok")
			}
		}
	}()
	return ln.Addr().String(), received
}

func TestSMTPSenderDeliversCode(t *testing.T) {
	addr, received := fakeSMTP(t)
	s := &SMTPSender{Addr: addr, From: "ivia <no-reply@ivia.local>"}
	if err := s.Send(context.Background(), ChannelEmail, "ama@example.tg", "482913"); err != nil {
		t.Fatalf("envoi : %v", err)
	}
	msg := <-received
	for _, want := range []string{"To: ama@example.tg", "Subject: Votre code de connexion ivia : 482913", "482913", "multipart/alternative"} {
		if !strings.Contains(msg, want) {
			t.Errorf("message sans %q :\n%s", want, msg)
		}
	}
}

func TestTeeSenderKeepsDevEndpointWorking(t *testing.T) {
	addr, received := fakeSMTP(t)
	logs := &LogSender{Logger: slog.New(slog.NewTextHandler(io.Discard, nil))}
	tee := TeeSender{&SMTPSender{Addr: addr, From: "no-reply@ivia.local"}, logs}
	if err := tee.Send(context.Background(), ChannelEmail, "kofi@example.tg", "111222"); err != nil {
		t.Fatal(err)
	}
	<-received
	if code, ok := logs.LastCode("kofi@example.tg"); !ok || code != "111222" {
		t.Fatalf("code non mémorisé pour POST /v1/dev/otp : %q", code)
	}
}
