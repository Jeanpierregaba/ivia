package storage

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"encoding/xml"
	"fmt"
	"io"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"time"
)

// R2 implémente ObjectStore avec Cloudflare R2 (API compatible S3, signature AWS SigV4).
type R2 struct {
	accountID     string
	accessKeyID   string
	secretKey     string
	publicBucket  string
	privateBucket string
	publicBaseURL string
	client        *http.Client
	now           func() time.Time
}

// R2Config regroupe les identifiants R2.
type R2Config struct {
	AccountID, AccessKeyID, SecretAccessKey string
	PublicBucket, PrivateBucket             string
	// PublicBaseURL : domaine public du compartiment des photos (ex. https://media.ivia.tg).
	PublicBaseURL string
}

// NewR2 crée le client R2.
func NewR2(cfg R2Config) *R2 {
	return &R2{
		accountID:     cfg.AccountID,
		accessKeyID:   cfg.AccessKeyID,
		secretKey:     cfg.SecretAccessKey,
		publicBucket:  cfg.PublicBucket,
		privateBucket: cfg.PrivateBucket,
		publicBaseURL: strings.TrimRight(cfg.PublicBaseURL, "/"),
		client:        &http.Client{Timeout: 10 * time.Second},
		now:           time.Now,
	}
}

func (r *R2) host() string { return r.accountID + ".r2.cloudflarestorage.com" }

func (r *R2) bucket(vis Visibility) string {
	if vis == Private {
		return r.privateBucket
	}
	return r.publicBucket
}

// PresignPut implémente ObjectStore.
func (r *R2) PresignPut(_ context.Context, vis Visibility, key, contentType string, size int64, ttl time.Duration) (PresignedRequest, error) {
	now := r.now().UTC()
	headers := map[string]string{"content-type": contentType, "content-length": strconv.FormatInt(size, 10)}
	u := presignV4(presignInput{
		method: http.MethodPut, host: r.host(), path: "/" + r.bucket(vis) + "/" + key,
		region: "auto", accessKey: r.accessKeyID, secretKey: r.secretKey,
		now: now, ttl: ttl, headers: headers,
	})
	return PresignedRequest{
		Method:    http.MethodPut,
		URL:       u,
		Headers:   map[string]string{"Content-Type": contentType, "Content-Length": strconv.FormatInt(size, 10)},
		ExpiresAt: now.Add(ttl),
	}, nil
}

// PresignGet implémente ObjectStore.
func (r *R2) PresignGet(_ context.Context, key string, ttl time.Duration) (string, error) {
	return presignV4(presignInput{
		method: http.MethodGet, host: r.host(), path: "/" + r.privateBucket + "/" + key,
		region: "auto", accessKey: r.accessKeyID, secretKey: r.secretKey,
		now: r.now().UTC(), ttl: ttl,
	}), nil
}

// PublicURL implémente ObjectStore.
func (r *R2) PublicURL(key string) string { return r.publicBaseURL + "/" + escapePath(key) }

// Exists implémente ObjectStore.
func (r *R2) Exists(ctx context.Context, vis Visibility, key string) (bool, error) {
	u := presignV4(presignInput{
		method: http.MethodHead, host: r.host(), path: "/" + r.bucket(vis) + "/" + key,
		region: "auto", accessKey: r.accessKeyID, secretKey: r.secretKey,
		now: r.now().UTC(), ttl: time.Minute,
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodHead, u, nil)
	if err != nil {
		return false, err
	}
	resp, err := r.client.Do(req)
	if err != nil {
		return false, fmt.Errorf("vérification du fichier sur R2 : %w", err)
	}
	_ = resp.Body.Close()
	switch resp.StatusCode {
	case http.StatusOK:
		return true, nil
	case http.StatusNotFound:
		return false, nil
	default:
		return false, fmt.Errorf("vérification du fichier sur R2 : statut %d", resp.StatusCode)
	}
}

// Delete implémente ObjectStore.
func (r *R2) Delete(ctx context.Context, vis Visibility, key string) error {
	u := presignV4(presignInput{
		method: http.MethodDelete, host: r.host(), path: "/" + r.bucket(vis) + "/" + key,
		region: "auto", accessKey: r.accessKeyID, secretKey: r.secretKey,
		now: r.now().UTC(), ttl: time.Minute,
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodDelete, u, nil)
	if err != nil {
		return err
	}
	resp, err := r.client.Do(req)
	if err != nil {
		return fmt.Errorf("suppression du fichier sur R2 : %w", err)
	}
	_ = resp.Body.Close()
	if resp.StatusCode != http.StatusNoContent && resp.StatusCode != http.StatusOK && resp.StatusCode != http.StatusNotFound {
		return fmt.Errorf("suppression du fichier sur R2 : statut %d", resp.StatusCode)
	}
	return nil
}

// List implémente ObjectStore (ListObjectsV2, 1000 clés par page, pages suivies jusqu'au bout).
func (r *R2) List(ctx context.Context, vis Visibility, prefix string) ([]Object, error) {
	var out []Object
	token := ""
	for {
		query := map[string]string{"list-type": "2", "prefix": prefix}
		if token != "" {
			query["continuation-token"] = token
		}
		u := presignV4(presignInput{
			method: http.MethodGet, host: r.host(), path: "/" + r.bucket(vis),
			region: "auto", accessKey: r.accessKeyID, secretKey: r.secretKey,
			now: r.now().UTC(), ttl: time.Minute, query: query,
		})
		req, err := http.NewRequestWithContext(ctx, http.MethodGet, u, nil)
		if err != nil {
			return nil, err
		}
		resp, err := r.client.Do(req)
		if err != nil {
			return nil, fmt.Errorf("liste des fichiers sur R2 : %w", err)
		}
		body, err := io.ReadAll(io.LimitReader(resp.Body, 16<<20))
		_ = resp.Body.Close()
		if err != nil {
			return nil, fmt.Errorf("liste des fichiers sur R2 : %w", err)
		}
		if resp.StatusCode != http.StatusOK {
			return nil, fmt.Errorf("liste des fichiers sur R2 : statut %d", resp.StatusCode)
		}
		var page struct {
			Contents []struct {
				Key          string    `xml:"Key"`
				LastModified time.Time `xml:"LastModified"`
			} `xml:"Contents"`
			IsTruncated           bool   `xml:"IsTruncated"`
			NextContinuationToken string `xml:"NextContinuationToken"`
		}
		if err := xml.Unmarshal(body, &page); err != nil {
			return nil, fmt.Errorf("liste des fichiers sur R2 : réponse illisible : %w", err)
		}
		for _, c := range page.Contents {
			out = append(out, Object{Key: c.Key, LastModified: c.LastModified})
		}
		if !page.IsTruncated || page.NextContinuationToken == "" {
			return out, nil
		}
		token = page.NextContinuationToken
	}
}

type presignInput struct {
	method, host, path   string
	region               string
	accessKey, secretKey string
	now                  time.Time
	ttl                  time.Duration
	// headers signés en plus de host (noms en minuscules).
	headers map[string]string
	// query : paramètres de la requête en plus de ceux de la signature (signés aussi).
	query map[string]string
}

// presignV4 construit une URL signée selon AWS Signature Version 4 (authentification par la
// chaîne de requête), service s3.
func presignV4(in presignInput) string {
	amzDate := in.now.Format("20060102T150405Z")
	date := in.now.Format("20060102")
	scope := date + "/" + in.region + "/s3/aws4_request"

	headers := map[string]string{"host": in.host}
	for k, v := range in.headers {
		headers[strings.ToLower(k)] = strings.TrimSpace(v)
	}
	names := make([]string, 0, len(headers))
	for k := range headers {
		names = append(names, k)
	}
	sort.Strings(names)
	var canonicalHeaders strings.Builder
	for _, k := range names {
		canonicalHeaders.WriteString(k + ":" + headers[k] + "\n")
	}
	signedHeaders := strings.Join(names, ";")

	query := map[string]string{
		"X-Amz-Algorithm":     "AWS4-HMAC-SHA256",
		"X-Amz-Credential":    in.accessKey + "/" + scope,
		"X-Amz-Date":          amzDate,
		"X-Amz-Expires":       strconv.Itoa(int(in.ttl.Seconds())),
		"X-Amz-SignedHeaders": signedHeaders,
	}
	for k, v := range in.query {
		query[k] = v
	}
	canonicalQuery := canonicalQueryString(query)
	canonicalURI := escapePath(in.path)

	canonicalRequest := strings.Join([]string{
		in.method, canonicalURI, canonicalQuery, canonicalHeaders.String(), signedHeaders, "UNSIGNED-PAYLOAD",
	}, "\n")
	hash := sha256.Sum256([]byte(canonicalRequest))
	stringToSign := "AWS4-HMAC-SHA256\n" + amzDate + "\n" + scope + "\n" + hex.EncodeToString(hash[:])

	key := hmacSHA256([]byte("AWS4"+in.secretKey), date)
	key = hmacSHA256(key, in.region)
	key = hmacSHA256(key, "s3")
	key = hmacSHA256(key, "aws4_request")
	signature := hex.EncodeToString(hmacSHA256(key, stringToSign))

	return "https://" + in.host + canonicalURI + "?" + canonicalQuery + "&X-Amz-Signature=" + signature
}

func canonicalQueryString(q map[string]string) string {
	keys := make([]string, 0, len(q))
	for k := range q {
		keys = append(keys, k)
	}
	sort.Strings(keys)
	parts := make([]string, len(keys))
	for i, k := range keys {
		parts[i] = uriEncode(k, true) + "=" + uriEncode(q[k], true)
	}
	return strings.Join(parts, "&")
}

// escapePath encode chaque segment du chemin (les « / » sont conservés).
func escapePath(p string) string {
	segments := strings.Split(p, "/")
	for i, s := range segments {
		segments[i] = uriEncode(s, true)
	}
	return strings.Join(segments, "/")
}

// uriEncode suit la RFC 3986 comme l'exige SigV4 : seuls A-Z a-z 0-9 - _ . ~ restent en clair.
func uriEncode(s string, encodeSlash bool) string {
	var b strings.Builder
	for _, c := range []byte(s) {
		switch {
		case c >= 'A' && c <= 'Z', c >= 'a' && c <= 'z', c >= '0' && c <= '9',
			c == '-', c == '_', c == '.', c == '~':
			b.WriteByte(c)
		case c == '/' && !encodeSlash:
			b.WriteByte(c)
		default:
			fmt.Fprintf(&b, "%%%02X", c)
		}
	}
	return b.String()
}

func hmacSHA256(key []byte, data string) []byte {
	h := hmac.New(sha256.New, key)
	h.Write([]byte(data))
	return h.Sum(nil)
}

var _ ObjectStore = (*R2)(nil)
