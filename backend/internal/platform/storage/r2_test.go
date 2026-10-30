package storage

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

// Vecteur officiel de la documentation AWS « Authenticating Requests: Using Query Parameters »
// (GET /test.txt sur examplebucket, 24/05/2013) : garantit que la signature SigV4 est exacte.
func TestPresignV4MatchesAWSReferenceVector(t *testing.T) {
	u := presignV4(presignInput{
		method:    http.MethodGet,
		host:      "examplebucket.s3.amazonaws.com",
		path:      "/test.txt",
		region:    "us-east-1",
		accessKey: "AKIAIOSFODNN7EXAMPLE",
		secretKey: "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY",
		now:       time.Date(2013, 5, 24, 0, 0, 0, 0, time.UTC),
		ttl:       86400 * time.Second,
	})
	const want = "aeeed9bbccd4d02ee5c0109b86d86835f995330da4c265957d157751f604d404"
	if !strings.HasSuffix(u, "&X-Amz-Signature="+want) {
		t.Fatalf("signature inattendue : %s", u)
	}
}

func TestR2PresignPutSignsTypeAndSize(t *testing.T) {
	r := NewR2(R2Config{AccountID: "acc", AccessKeyID: "ak", SecretAccessKey: "sk", PublicBucket: "pub", PrivateBucket: "priv"})
	req, err := r.PresignPut(context.Background(), Private, "drivers/u1/doc.pdf", "application/pdf", 1234, 5*time.Minute)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.HasPrefix(req.URL, "https://acc.r2.cloudflarestorage.com/priv/drivers/u1/doc.pdf?") {
		t.Fatalf("URL inattendue : %s", req.URL)
	}
	if !strings.Contains(req.URL, "X-Amz-SignedHeaders=content-length%3Bcontent-type%3Bhost") {
		t.Fatalf("type et taille doivent être signés : %s", req.URL)
	}
	if req.Headers["Content-Length"] != "1234" || req.Headers["Content-Type"] != "application/pdf" {
		t.Fatalf("en-têtes inattendus : %v", req.Headers)
	}
}

func TestLocalStoreRoundTrip(t *testing.T) {
	l := NewLocal(t.TempDir(), "http://api.test", []byte("secret-de-test"))
	srv := httptest.NewServer(l.Handler())
	defer srv.Close()
	l.baseURL = srv.URL
	ctx := context.Background()

	body := "contenu"
	req, _ := l.PresignPut(ctx, Private, "drivers/u1/a.pdf", "application/pdf", int64(len(body)), time.Minute)

	put := func(ct string) int {
		hr, _ := http.NewRequest(http.MethodPut, req.URL, strings.NewReader(body))
		hr.Header.Set("Content-Type", ct)
		resp, err := http.DefaultClient.Do(hr)
		if err != nil {
			t.Fatal(err)
		}
		resp.Body.Close()
		return resp.StatusCode
	}
	if code := put("image/png"); code != http.StatusForbidden {
		t.Fatalf("type différent de celui signé : statut %d, attendu 403", code)
	}
	if code := put("application/pdf"); code != http.StatusOK {
		t.Fatalf("envoi : statut %d", code)
	}
	if ok, _ := l.Exists(ctx, Private, "drivers/u1/a.pdf"); !ok {
		t.Fatal("le fichier devrait exister")
	}

	// Un fichier privé ne se lit pas sans signature.
	resp, _ := http.Get(srv.URL + "/dev/storage/private/drivers/u1/a.pdf")
	resp.Body.Close()
	if resp.StatusCode != http.StatusForbidden {
		t.Fatalf("lecture sans signature : statut %d, attendu 403", resp.StatusCode)
	}
	signed, _ := l.PresignGet(ctx, "drivers/u1/a.pdf", time.Minute)
	resp, _ = http.Get(signed)
	resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("lecture signée : statut %d", resp.StatusCode)
	}

	if ok, _ := l.Exists(ctx, Public, "../../etc/passwd"); ok {
		t.Fatal("une clé hors du dossier ne doit jamais être acceptée")
	}
}
