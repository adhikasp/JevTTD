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
 * Choice/Score/Noul/ScoreAndChoose below are all local (AIBase.RandRange),
 * and that stays the baseline this AI always works on stock OpenTTD with.
 *
 * The companion engine fork (adhikasp/OpenTTD, branch feature/ai-decision-http)
 * has since landed a real opt-in AIDecision.IsAvailable()/AIDecision.Ask()
 * API - RemoteAvailable()/RemoteAsk() below are thin passthroughs to it.
 * Deliberately NOT wired into Choice/Score/Noul yet: AIDecision.Ask() is a
 * dumb opaque JSON-in/JSON-out relay (see that engine PR's design notes),
 * and picking the actual request/response JSON shape is a protocol decision
 * that shouldn't be made silently in a plumbing pass - do that once we know
 * what's on the other end of script.decision_service_url (a real TypeSafe.ai
 * adapter vs. a local mock vs. something else).
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

	/**
	 * Whether a remote decision call could plausibly succeed right now
	 * (single-player, player opted in via script.allow_decision_calls, and
	 * script.decision_service_url is set). Cheap; safe to call every time
	 * before deciding whether to bother building a request.
	 */
	static function RemoteAvailable();

	/**
	 * Send a raw JSON request to the locally configured decision service
	 * and suspend this script until a response arrives. Thin passthrough to
	 * AIDecision.Ask() - see the file header for why this isn't wired into
	 * Choice/Score/Noul yet.
	 * @param request_json The request body, already JSON-encoded by the caller.
	 * @return The response body as a string, or null on any failure.
	 */
	static function RemoteAsk(request_json);
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

function FunBrain::RemoteAvailable()
{
	/* AIDecision only exists on the companion engine fork; on stock OpenTTD
	 * it's simply not registered, and calling AIDecision.IsAvailable()
	 * directly would throw a runtime "the index 'AIDecision' does not
	 * exist" error the first time this ran. Check the root table first so
	 * this just reports "unavailable" on a vanilla client instead. */
	if (!("AIDecision" in getroottable())) return false;
	return AIDecision.IsAvailable();
}

function FunBrain::RemoteAsk(request_json)
{
	if (!FunBrain.RemoteAvailable()) return null;
	return AIDecision.Ask(request_json);
}
