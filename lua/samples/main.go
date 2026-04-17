package main

import (
	"cmp"
	"database/sql"
	"fmt"
	"math/rand"
	"regexp"
	"slices"
	"sync"
	"time"
)

// safeIdentifier matches a simple `table` or `schema.table` pattern used to
// guard DBCount against SQL injection — driver parameters cannot be used for
// identifiers, so we validate the shape ourselves.
var safeIdentifier = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)?$`)

// DBCount returns the row count of the given table (`SELECT count(*) FROM <table>`).
// The table name must match a conservative identifier pattern.
func DBCount(db *sql.DB, table string) (int64, error) {
	if !safeIdentifier.MatchString(table) {
		return 0, fmt.Errorf("invalid table name: %q", table)
	}
	var n int64
	if err := db.QueryRow(fmt.Sprintf("SELECT count(*) FROM %s", table)).Scan(&n); err != nil {
		return 0, fmt.Errorf("count %s: %w", table, err)
	}
	return n, nil
}

func main() {
	const n = 1000
	data := make([]int, n)
	for i := range data {
		data[i] = rand.Intn(1_000_000)
	}

	jobs := []struct {
		name string
		sort func([]int)
	}{
		{"bubble", func(s []int) { BubbleSort(s) }},
		{"binary", func(s []int) { BinarySort(s) }},
		{"heap", func(s []int) { HeapSort(s) }},
	}

	var wg sync.WaitGroup
	for _, job := range jobs {
		wg.Add(1)
		go func(name string, sortFn func([]int)) {
			defer wg.Done()
			buf := slices.Clone(data)
			start := time.Now()
			fmt.Printf("[%s] start: %s\n", name, start.Format(time.RFC3339Nano))
			sortFn(buf)
			end := time.Now()
			fmt.Printf("[%s] end:   %s (took %s)\n", name, end.Format(time.RFC3339Nano), end.Sub(start))
		}(job.name, job.sort)
	}
	wg.Wait()
}

// resolveCmp returns the first user-supplied comparator, or cmp.Compare as default.
func resolveCmp[T cmp.Ordered](cmpFn []func(a, b T) int) func(a, b T) int {
	if len(cmpFn) > 0 && cmpFn[0] != nil {
		return cmpFn[0]
	}
	return cmp.Compare[T]
}

// BubbleSort sorts s in place. Optional cmpFn overrides the default ordering.
func BubbleSort[T cmp.Ordered](s []T, cmpFn ...func(a, b T) int) {
	compare := resolveCmp(cmpFn)
	n := len(s)
	for i := 0; i < n-1; i++ {
		swapped := false
		for j := 0; j < n-i-1; j++ {
			if compare(s[j], s[j+1]) > 0 {
				s[j], s[j+1] = s[j+1], s[j]
				swapped = true
			}
		}
		if !swapped {
			return
		}
	}
}

// BinarySort (binary insertion sort): finds each insertion point via binary search.
// O(n log n) comparisons, O(n^2) element moves.
func BinarySort[T cmp.Ordered](s []T, cmpFn ...func(a, b T) int) {
	compare := resolveCmp(cmpFn)
	for i := 1; i < len(s); i++ {
		key := s[i]
		lo, hi := 0, i
		for lo < hi {
			mid := int(uint(lo+hi) >> 1)
			if compare(s[mid], key) <= 0 {
				lo = mid + 1
			} else {
				hi = mid
			}
		}
		copy(s[lo+1:i+1], s[lo:i])
		s[lo] = key
	}
}

// HeapSort sorts s in place with an in-place max-heap.
func HeapSort[T cmp.Ordered](s []T, cmpFn ...func(a, b T) int) {
	compare := resolveCmp(cmpFn)
	n := len(s)
	for i := n/2 - 1; i >= 0; i-- {
		siftDown(s, i, n, compare)
	}
	for i := n - 1; i > 0; i-- {
		s[0], s[i] = s[i], s[0]
		siftDown(s, 0, i, compare)
	}
}

func siftDown[T cmp.Ordered](s []T, start, end int, compare func(a, b T) int) {
	root := start
	for {
		child := 2*root + 1
		if child >= end {
			return
		}
		if child+1 < end && compare(s[child], s[child+1]) < 0 {
			child++
		}
		if compare(s[root], s[child]) >= 0 {
			return
		}
		s[root], s[child] = s[child], s[root]
		root = child
	}
}
