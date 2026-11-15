package database

import (
	"context"
	"errors"
	"fmt"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// DBTX est l'interface attendue par le code généré par sqlc : un pool ou une transaction.
type DBTX interface {
	Exec(ctx context.Context, sql string, args ...any) (pgconn.CommandTag, error)
	Query(ctx context.Context, sql string, args ...any) (pgx.Rows, error)
	QueryRow(ctx context.Context, sql string, args ...any) pgx.Row
}

// DB donne accès à la base. La transaction en cours voyage dans le contexte : un service appelé
// pendant une transaction ouverte par un autre service y participe automatiquement. C'est ce qui
// permet, par exemple, de créer une commande, réserver le stock et planifier l'expiration du
// paiement de façon atomique sans qu'un module touche aux tables d'un autre.
type DB struct {
	Pool *pgxpool.Pool
}

// New enveloppe un pool de connexions.
func New(pool *pgxpool.Pool) *DB { return &DB{Pool: pool} }

type txKey struct{}

// TxFromContext retourne la transaction en cours, s'il y en a une.
func TxFromContext(ctx context.Context) (pgx.Tx, bool) {
	tx, ok := ctx.Value(txKey{}).(pgx.Tx)
	return tx, ok
}

// Conn retourne la transaction en cours ou, à défaut, le pool.
func (d *DB) Conn(ctx context.Context) DBTX {
	if tx, ok := TxFromContext(ctx); ok {
		return tx
	}
	return d.Pool
}

// InTx exécute fn dans une transaction. Si une transaction est déjà en cours dans ctx, fn y
// participe (pas de transaction imbriquée) : c'est l'appelant le plus externe qui valide.
func (d *DB) InTx(ctx context.Context, fn func(ctx context.Context) error) error {
	if _, ok := TxFromContext(ctx); ok {
		return fn(ctx)
	}
	tx, err := d.Pool.Begin(ctx)
	if err != nil {
		return fmt.Errorf("ouverture de transaction : %w", err)
	}
	defer func() { _ = tx.Rollback(context.WithoutCancel(ctx)) }()

	if err := fn(context.WithValue(ctx, txKey{}, tx)); err != nil {
		return err
	}
	if err := tx.Commit(ctx); err != nil {
		return fmt.Errorf("validation de transaction : %w", err)
	}
	return nil
}

// Savepoint exécute fn dans un point de sauvegarde de la transaction en cours : si fn échoue,
// seules ses écritures sont annulées et la transaction englobante continue. Sans transaction en
// cours, se comporte comme InTx.
func (d *DB) Savepoint(ctx context.Context, fn func(ctx context.Context) error) error {
	outer, ok := TxFromContext(ctx)
	if !ok {
		return d.InTx(ctx, fn)
	}
	sp, err := outer.Begin(ctx)
	if err != nil {
		return fmt.Errorf("point de sauvegarde : %w", err)
	}
	if err := fn(context.WithValue(ctx, txKey{}, sp)); err != nil {
		if rbErr := sp.Rollback(ctx); rbErr != nil {
			return errors.Join(err, rbErr)
		}
		return err
	}
	return sp.Commit(ctx)
}

// Codes d'erreur PostgreSQL utilisés par les services.
const (
	codeUniqueViolation = "23505"
	codeCheckViolation  = "23514"
	codeForeignKey      = "23503"
)

// IsUniqueViolation indique une violation de contrainte d'unicité, éventuellement sur une contrainte précise.
func IsUniqueViolation(err error, constraint string) bool {
	return isPgError(err, codeUniqueViolation, constraint)
}

// IsCheckViolation indique une violation de contrainte CHECK, éventuellement sur une contrainte précise.
func IsCheckViolation(err error, constraint string) bool {
	return isPgError(err, codeCheckViolation, constraint)
}

// IsForeignKeyViolation indique une référence vers une ligne absente.
func IsForeignKeyViolation(err error) bool { return isPgError(err, codeForeignKey, "") }

// IsNoRows indique qu'une requête :one n'a trouvé aucune ligne.
func IsNoRows(err error) bool { return errors.Is(err, pgx.ErrNoRows) }

func isPgError(err error, code, constraint string) bool {
	var pgErr *pgconn.PgError
	if !errors.As(err, &pgErr) || pgErr.Code != code {
		return false
	}
	return constraint == "" || pgErr.ConstraintName == constraint
}
