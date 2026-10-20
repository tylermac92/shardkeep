class_name Streams
extends RefCounted
## Counter-based random streams (technical_design.md, Randomness). The n-th value of a
## stream is a pure hash of (battle seed, stream, n), and the only state is how many values
## each stream has used, so a clone can never advance the original's streams.

## Stream ids. They are hashed into every value: reordering them changes every battle.
## Column x is COL_0 + x; side s's AI stream is AI_0 + s.
enum { COL_0, COL_1, COL_2, COL_3, COL_4, COL_5, COL_6, COL_7, SETUP, SHUFFLE, EFFECTS, AI_0, AI_1, LOOT, COUNT }

const MASK := 0xFFFFFFFF

var battle_seed: int
## Values used so far, per stream id.
var draws := PackedInt32Array()


func _init(seed_value: int = 0) -> void:
	battle_seed = seed_value
	draws.resize(COUNT)


func clone() -> Streams:
	var c := Streams.new(battle_seed)
	c.draws = draws.duplicate()
	return c


## Next value of the stream, in [0, 2^32).
func next_int(stream: int) -> int:
	var v := mix(battle_seed, stream, draws[stream])
	draws[stream] += 1
	return v


## Index into weights, picked in proportion to its weight. Uses one value of the stream.
func next_weighted(stream: int, weights: PackedInt32Array) -> int:
	var total := 0
	for w in weights:
		total += w
	assert(total > 0, "next_weighted needs a positive total weight")
	var r := next_int(stream) % total  # modulo bias is at most total / 2^32
	for i in weights.size():
		r -= weights[i]
		if r < 0:
			return i
	return -1


## murmur3_x86_32 of the words [seed low, seed high, stream, n] with hash seed 0.
static func mix(seed_value: int, stream: int, n: int) -> int:
	var h := _round(0, seed_value & MASK)
	h = _round(h, (seed_value >> 32) & MASK)
	h = _round(h, stream & MASK)
	h = _round(h, n & MASK)
	h ^= 16  # input length in bytes
	h ^= h >> 16
	h = _mul(h, 0x85ebca6b)
	h ^= h >> 13
	h = _mul(h, 0xc2b2ae35)
	return h ^ (h >> 16)


static func _round(h: int, k: int) -> int:
	k = _rotl(_mul(k, 0xcc9e2d51), 15)
	h = _rotl(h ^ _mul(k, 0x1b873593), 13)
	return (_mul(h, 5) + 0xe6546b64) & MASK


## 32-bit multiply. b is split into 16-bit halves so no product needs more than 48 bits.
static func _mul(a: int, b: int) -> int:
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & MASK


static func _rotl(x: int, r: int) -> int:
	return ((x << r) | (x >> (32 - r))) & MASK
