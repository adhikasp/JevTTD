/*
 * This file is part of JevTTD.
 *
 * JevTTD is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 2 of the License, or
 * (at your option) any later version.
 *
 * JevTTD is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU General Public License for more details.
 */

/**
 * @file funbrain.nut Local reimplementation of TypeSafe.ai's typed decision
 * primitives (Choice / Score / Noul), used to pick "fun" actions instead of
 * "optimal" ones.
 *
 * There is deliberately no network call anywhere in this file. OpenTTD's AI
 * sandbox exposes no HTTP capability to scripts (see the project README), so
 * everything here resolves locally using AIBase.RandRange. If a future
 * engine build exposes an opt-in remote-decision API, this is the one file
 * that would grow a remote-first path with this local logic kept as the
 * fallback - nothing else in the AI needs to know the difference.
 */

class FunBrain {
	/**
	 * Weighted random choice among options. Does NOT always return the
	 * highest-weighted option - that's the point. Higher weight just means
	 * more likely, not guaranteed.
	 * @param options Array of arbitrary values.
	 * @param weights Array of non-negative numbers, same length as options.
	 * @return One element of `options`.
	 */
	static function Choice(options, weights);

	/**
	 * Score every candidate against a rubric function.
	 * @param candidates Array of candidates.
	 * @param rubric A function(candidate, context) -> float. Higher is "more fun".
	 * @param context Arbitrary context passed through to the rubric (e.g. current Mood).
	 * @return Array of [candidate, score] pairs, sorted descending by score.
	 */
	static function Score(candidates, rubric, context);

	/**
	 * Soft boolean: true with probability `p` (0..1). Named after TypeSafe.ai's
	 * "Noul" primitive - use this instead of a hard `if (x > threshold)` when
	 * you want the AI to occasionally surprise you.
	 * @param p Probability of returning true, 0.0-1.0.
	 */
	static function Noul(p);

	/**
	 * Convenience: score candidates, then weighted-sample among the top `pool_size`
	 * of them instead of always taking #1. This is the "Speculative Fan-Out ->
	 * weighted pick" pattern from the README in one call.
	 * @param candidates Array of candidates.
	 * @param rubric A function(candidate, context) -> float.
	 * @param context Arbitrary context passed through to the rubric.
	 * @param pool_size How many of the top-scored candidates to sample from.
	 * @return A single chosen candidate, or null if `candidates` is empty.
	 */
	static function ScoreAndChoose(candidates, rubric, context, pool_size);
}

function FunBrain::Choice(options, weights)
{
	assert(options.len() == weights.len());
	if (options.len() == 0) return null;

	local total = 0.0;
	foreach (w in weights) total += w;
	if (total <= 0) return options[AIBase.RandRange(options.len())];

	local roll = (AIBase.RandRange(1000000).tofloat() / 1000000.0) * total;
	local acc = 0.0;
	for (local i = 0; i < options.len(); i++) {
		acc += weights[i];
		if (roll <= acc) return options[i];
	}
	return options.top();
}

function FunBrain::Score(candidates, rubric, context)
{
	local scored = [];
	foreach (c in candidates) {
		scored.push([c, rubric(c, context)]);
	}
	scored.sort(function(a, b) {
		if (a[1] < b[1]) return 1;
		if (a[1] > b[1]) return -1;
		return 0;
	});
	return scored;
}

function FunBrain::Noul(p)
{
	return (AIBase.RandRange(1000000).tofloat() / 1000000.0) < p;
}

function FunBrain::ScoreAndChoose(candidates, rubric, context, pool_size)
{
	if (candidates.len() == 0) return null;

	local scored = FunBrain.Score(candidates, rubric, context);
	local pool = [];
	local weights = [];
	local n = min(pool_size, scored.len());
	for (local i = 0; i < n; i++) {
		pool.push(scored[i][0]);
		/* Shift scores so the weakest of the pool still has a nonzero chance. */
		weights.push(scored[i][1] - scored[n - 1][1] + 1.0);
	}
	return FunBrain.Choice(pool, weights);
}
