package main

import (
	"cmp"
	"database/sql"
	"fmt"
	"math/rand"
	"os"
	"slices"
	"testing"

	_ "github.com/lib/pq"
)

// sortFn is the signature shared by all three sorts (variadic comparator).
type sortFn func([]int, ...func(a, b int) int)

var sorters = map[string]sortFn{
	"BubbleSort": BubbleSort[int],
	"BinarySort": BinarySort[int],
	"HeapSort":   HeapSort[int],
}

func TestSortCorrectness(t *testing.T) {
	cases := []struct {
		name  string
		input []int
	}{
		{"empty", []int{}},
		{"single", []int{42}},
		{"already_sorted", []int{1, 2, 3, 4, 5}},
		{"reverse_sorted", []int{5, 4, 3, 2, 1}},
		{"duplicates", []int{3, 1, 2, 3, 1, 2}},
		{"negatives", []int{-3, 5, -1, 0, 2, -8}},
		{"random_small", []int{9, 2, 7, 1, 8, 3, 6, 4, 5}},
	}

	for name, sort := range sorters {
		for _, tc := range cases {
			t.Run(name+"/"+tc.name, func(t *testing.T) {
				got := slices.Clone(tc.input)
				want := slices.Clone(tc.input)
				slices.Sort(want)

				sort(got)

				if !slices.Equal(got, want) {
					t.Errorf("%s(%v) = %v, want %v", name, tc.input, got, want)
				}
			})
		}
	}
}

func TestSortRandomLarge(t *testing.T) {
	rng := rand.New(rand.NewSource(42))
	input := make([]int, 1000)
	for i := range input {
		input[i] = rng.Intn(1_000_000)
	}
	want := slices.Clone(input)
	slices.Sort(want)

	for name, sort := range sorters {
		t.Run(name, func(t *testing.T) {
			got := slices.Clone(input)
			sort(got)
			if !slices.Equal(got, want) {
				t.Errorf("%s produced incorrect result", name)
			}
		})
	}
}

func TestSortCustomComparator(t *testing.T) {
	desc := func(a, b int) int { return cmp.Compare(b, a) }
	input := []int{3, 1, 4, 1, 5, 9, 2, 6, 5, 3}
	want := []int{9, 6, 5, 5, 4, 3, 3, 2, 1, 1}

	for name, sort := range sorters {
		t.Run(name, func(t *testing.T) {
			got := slices.Clone(input)
			sort(got, desc)
			if !slices.Equal(got, want) {
				t.Errorf("%s desc = %v, want %v", name, got, want)
			}
		})
	}
}

// DB integration test — reads TEST_PGURL from the environment.
// Runs against a live Postgres and expects an `artist` table.

func TestDBCount(t *testing.T) {
	url := os.Getenv("TEST_PGURL")
	if url == "" {
		t.Skip("TEST_PGURL not set; skipping live Postgres test")
	}

	db, err := sql.Open("postgres", url)
	if err != nil {
		t.Fatalf("sql.Open: %v", err)
	}
	defer db.Close()

	if err := db.Ping(); err != nil {
		t.Fatalf("db.Ping: %v", err)
	}

	n, err := DBCount(db, "artist")
	if err != nil {
		t.Fatalf("DBCount: %v", err)
	}
	t.Logf("artist row count = %d", n)
}

// Benchmarks

func benchmarkSort(b *testing.B, sort sortFn, n int) {
	rng := rand.New(rand.NewSource(1))
	base := make([]int, n)
	for i := range base {
		base[i] = rng.Intn(1_000_000)
	}
	buf := make([]int, n)

	b.ResetTimer()
	for i := 0; i < b.N; i++ {
		copy(buf, base)
		sort(buf)
	}
}

var benchSizes = []int{100, 1000, 10_000}

func BenchmarkBubbleSort(b *testing.B) {
	for _, n := range benchSizes {
		b.Run(fmt.Sprintf("N=%d", n), func(b *testing.B) { benchmarkSort(b, BubbleSort[int], n) })
	}
}

func BenchmarkBinarySort(b *testing.B) {
	for _, n := range benchSizes {
		b.Run(fmt.Sprintf("N=%d", n), func(b *testing.B) { benchmarkSort(b, BinarySort[int], n) })
	}
}

func BenchmarkHeapSort(b *testing.B) {
	for _, n := range benchSizes {
		b.Run(fmt.Sprintf("N=%d", n), func(b *testing.B) { benchmarkSort(b, HeapSort[int], n) })
	}
}
