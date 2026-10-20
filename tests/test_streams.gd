extends GutTest

## [seed, stream, n, expected]. Expected values come from an independent murmur3:
## Python mmh3.hash(struct.pack("<4I", seed & M, (seed >> 32) & M, stream, n), 0, signed=False)
const GOLDEN := [
	[0, 0, 0, 2167721464],
	[0, 0, 1, 10027521],
	[1, 0, 0, 2451737883],
	[42, 8, 0, 3347377587],
	[42, 8, 1, 1377009658],
	[42, 9, 7, 4178325928],
	[42, 10, 123, 4202615566],
	[42, 11, 5, 1712561981],
	[42, 12, 5, 4135635496],
	[42, 13, 0, 26099261],
	[-1, 0, 0, 1040203207],
	[-1, 7, 999, 524643781],
	[123456789012345, 3, 2, 1007445476],
	[-1234567890123, 4, 77, 697749968],
	[9223372036854775807, 13, 2147483647, 733881263],
	[9223372036854775807, 0, 0, 1490104744],
	[4294967295, 1, 1, 4004077398],
	[4294967296, 1, 1, 2203301246],
	[987654321, 6, 65535, 3874389688],
	[987654321, 5, 65536, 1426034241],
]


func test_mix_golden_table() -> void:
	for row in GOLDEN:
		assert_eq(Streams.mix(row[0], row[1], row[2]), row[3], "mix(%d, %d, %d)" % [row[0], row[1], row[2]])


func test_next_int_walks_the_stream_and_counts() -> void:
	var s := Streams.new(42)
	assert_eq(s.next_int(Streams.SETUP), Streams.mix(42, Streams.SETUP, 0))
	assert_eq(s.next_int(Streams.SETUP), Streams.mix(42, Streams.SETUP, 1))
	assert_eq(s.draws[Streams.SETUP], 2)
	assert_eq(s.draws[Streams.SHUFFLE], 0, "other streams don't advance")


func test_weighted_draws_match_gem_weights() -> void:
	var loader := ContentLoader.new()
	loader.load_all()
	var weights := loader.gem_weights
	assert_eq(weights, PackedInt32Array([16, 16, 16, 16, 12, 12, 12]), "weights loaded in GEM_IDS order")
	var total := 0
	for w in weights:
		total += w
	var counts := PackedInt32Array()
	counts.resize(weights.size())
	var s := Streams.new(20261020)
	const DRAWS := 100000
	for i in DRAWS:
		counts[s.next_weighted(Streams.COL_0, weights)] += 1
	for i in weights.size():
		var share := 100.0 * counts[i] / DRAWS
		var want := 100.0 * weights[i] / total
		assert_almost_eq(share, want, 1.0, "%s share (%%)" % ContentLoader.GEM_IDS[i])


func test_zero_weight_is_never_drawn() -> void:
	var s := Streams.new(7)
	for i in 1000:
		assert_ne(s.next_weighted(Streams.EFFECTS, PackedInt32Array([1, 0, 1])), 1)
		if is_failing():
			return


func test_streams_are_unrelated() -> void:
	var values: Array[PackedInt64Array] = []
	for stream in Streams.COUNT:
		var v := PackedInt64Array()
		for n in 1000:
			v.append(Streams.mix(99, stream, n))
		values.append(v)
	for a in Streams.COUNT:
		for b in range(a + 1, Streams.COUNT):
			for n in 1000:
				if values[a][n] == values[b][n]:
					fail_test("streams %d and %d match at n=%d" % [a, b, n])
					return
	pass_test("no stream pair matches position by position")


func test_clone_does_not_share_counters() -> void:
	var s := Streams.new(5)
	s.next_int(Streams.LOOT)
	var c := s.clone()
	c.next_int(Streams.LOOT)
	c.next_int(Streams.COL_3)
	assert_eq(s.draws[Streams.LOOT], 1)
	assert_eq(s.draws[Streams.COL_3], 0)
	assert_eq(s.next_int(Streams.LOOT), Streams.mix(5, Streams.LOOT, 1))
