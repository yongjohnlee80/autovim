package billing

import (
	"context"
	"fmt"
	"time"
)

type InvoiceRequest struct {
	AccountID string
	Amount   int64
	Currency string
	DueAt    time.Time
}

type InvoiceResult struct {
	ID     string
	Status string
}

type Ledger interface {
	Reserve(ctx context.Context, accountID string, amount int64) error
	RecordInvoice(ctx context.Context, req InvoiceRequest) (string, error)
}

type Service struct {
	ledger Ledger
}

func NewService(ledger Ledger) *Service {
	return &Service{ledger: ledger}
}

func (s *Service) CreateInvoice(ctx context.Context, req InvoiceRequest) (InvoiceResult, error) {
	if req.AccountID == "" {
		return InvoiceResult{}, fmt.Errorf("account id is required")
	}
	if req.Amount <= 0 {
		return InvoiceResult{}, fmt.Errorf("amount must be positive")
	}
	if err := s.ledger.Reserve(ctx, req.AccountID, req.Amount); err != nil {
		return InvoiceResult{}, fmt.Errorf("reserve funds: %w", err)
	}
	id, err := s.ledger.RecordInvoice(ctx, req)
	if err != nil {
		return InvoiceResult{}, fmt.Errorf("record invoice: %w", err)
	}
	return InvoiceResult{ID: id, Status: "pending"}, nil
}
