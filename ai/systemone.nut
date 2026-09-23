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
 * @file systemone.nut Talks the real Jev "System One" protocol
 * (POST /v1/systemone) over FunBrain.RemoteAsk()/AIDecision.Ask(), against
 * a locally running Jev-compatible server (laya-serve, or real TypeSafe.ai
 * if someone points script.decision_service_url at a compatible bridge).
 *
 * Schema below was captured from a live laya-serve response, not guessed:
 *
 *   request:  {"state": <string>, "model": "jev-latest", "questions": {
 *                "<key>": {"type": "choice", "instructions": <string>, "criteria": {<key>: <description>, ...}}
 *              | {"type": "noul",   "instructions": <string>}
 *              | {"type": "score",  "instructions": <string>, "criteria": [<level0 desc>, <level1 desc>, ...]}
 *   }}
 *   response: {"model": ..., "answers": {"<key>": {
 *                "type": "choice", "choice": <key>, "probabilities": {...}, "confidence": <0..1>
 *              | "type": "noul",   "noul": <0..1>, "confidence": <0..1>
 *              | "type": "score",  "score": <float>, "legend": {...}, "probabilities": {...}, "confidence": <0..1>
 *   }}, "usage": {...}, "routing": {...}}
 *
 * Every function here returns null on any failure (server down, malformed
 * response, RemoteAvailable() false, ...) - callers always need a local
 * FunBrain fallback regardless, so there is no separate error channel.
 */

class SystemOne {
	/**
	 * Ask a multiple-choice question.
	 * @param state Freeform text describing the situation.
	 * @param instructions The question to ask.
	 * @param criteria A table of {option_key: description, ...}.
	 * @return [chosen_key, confidence] or null on failure.
	 */
	static function Choice(state, instructions, criteria);

	/**
	 * Ask a yes/no-ish question.
	 * @param state Freeform text describing the situation.
	 * @param instructions The question to ask.
	 * @return [value (0.0-1.0), confidence] or null on failure.
	 */
	static function Noul(state, instructions);

	/**
	 * Ask an ordinal scoring question.
	 * @param state Freeform text describing the situation.
	 * @param instructions The question to ask.
	 * @param levels Array of level descriptions, index 0 first (2-10 entries).
	 * @return [score (float, 0..levels.len()-1), confidence] or null on failure.
	 */
	static function Score(state, instructions, levels);

	/** Shared plumbing: send one single-question request, return its raw answer table or null. */
	static function AskOne(state, question_key, question);
}

function SystemOne::AskOne(state, question_key, question)
{
	if (!FunBrain.RemoteAvailable()) return null;

	local questions = {};
	questions.rawset(question_key, question);
	local request = {
		state = state,
		model = "jev-latest",
		questions = questions,
	};

	local request_json = null;
	try {
		request_json = Json.Encode(request);
	} catch (e) {
		AILog.Warning("SystemOne: failed to encode request: " + e);
		return null;
	}

	local response_json = FunBrain.RemoteAsk(request_json);
	if (response_json == null) return null;

	local response = null;
	try {
		response = Json.Decode(response_json);
	} catch (e) {
		AILog.Warning("SystemOne: failed to decode response: " + e);
		return null;
	}

	if (!(typeof(response) == "table" && response.rawin("answers"))) return null;
	local answers = response.rawget("answers");
	if (!answers.rawin(question_key)) return null;
	return answers.rawget(question_key);
}

function SystemOne::Choice(state, instructions, criteria)
{
	local answer = SystemOne.AskOne(state, "q", {
		type = "choice",
		instructions = instructions,
		criteria = criteria,
	});
	if (answer == null || !answer.rawin("choice")) return null;
	local confidence = answer.rawin("confidence") ? answer.rawget("confidence") : 0.0;
	return [answer.rawget("choice"), confidence];
}

function SystemOne::Noul(state, instructions)
{
	local answer = SystemOne.AskOne(state, "q", {
		type = "noul",
		instructions = instructions,
	});
	if (answer == null || !answer.rawin("noul")) return null;
	local confidence = answer.rawin("confidence") ? answer.rawget("confidence") : 0.0;
	return [answer.rawget("noul"), confidence];
}

function SystemOne::Score(state, instructions, levels)
{
	local answer = SystemOne.AskOne(state, "q", {
		type = "score",
		instructions = instructions,
		criteria = levels,
	});
	if (answer == null || !answer.rawin("score")) return null;
	local confidence = answer.rawin("confidence") ? answer.rawget("confidence") : 0.0;
	return [answer.rawget("score"), confidence];
}
