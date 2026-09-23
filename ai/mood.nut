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
 * @file mood.nut The Intent Router: classifies the current game state into a
 * Mood relative to the human player, so the (not-yet-written) route managers
 * can dispatch to different behavior instead of always doing the single
 * "best" thing. Real trigger heuristics are still coarse - see TODOs.
 */

enum Mood {
	SETTLER,  ///< Default/neutral: still finding its feet, no strong read on the game yet.
	UNDERDOG, ///< Clearly behind the strongest rival: bold, cheap, catch-up plays.
	RIVAL,    ///< Competing head-on for the same towns/industries as the player.
	SHOWMAN,  ///< Comfortably ahead: spend on spectacle instead of more optimal filler.
	COPYCAT,  ///< Mirror something the player just did.
	RECOVERY, ///< Just took a big loss: visible panic-sell, then dramatic rebuild.
}

class MoodEngine {
	current = null;
	last_evaluated = null;
	last_balance = null;

	constructor()
	{
		this.current = Mood.SETTLER;
		this.last_evaluated = 0;
		this.last_balance = null;
	}

	/**
	 * Re-evaluate the current mood if enough time has passed, otherwise
	 * return the cached value. Cheap to call every loop iteration.
	 */
	function Evaluate();

	/** @return Human-readable name for logging. */
	static function ToString(mood);

	/** @return One-line description used as a SystemOne criteria entry. */
	static function Describe(mood);
}

function MoodEngine::Evaluate()
{
	local today = AIDate.GetCurrentDate();
	if (today - this.last_evaluated < 30 && this.last_evaluated != 0) return this.current;
	this.last_evaluated = today;

	local my_balance = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
	local just_lost_money = this.last_balance != null && my_balance < this.last_balance * 0.7;
	this.last_balance = my_balance;

	local my_value = AICompany.GetQuarterlyCompanyValue(AICompany.COMPANY_SELF, 0);

	local candidates = [Mood.SETTLER, Mood.RIVAL, Mood.COPYCAT];
	local weights = [2.0, 2.0, 1.0];

	/* There is no AICompanyList - OpenTTD's Script API doesn't expose company
	 * enumeration as a list class like it does for towns/stations/industries.
	 * The idiom (matching AdmiralAI and friends) is to walk the fixed
	 * COMPANY_FIRST..COMPANY_LAST range and skip slots ResolveCompanyID()
	 * says are empty. */
	local my_company = AICompany.ResolveCompanyID(AICompany.COMPANY_SELF);
	local rival_value = 0;
	local found_rival = false;
	for (local c = AICompany.COMPANY_FIRST; c < AICompany.COMPANY_LAST; c++) {
		if (c == my_company) continue;
		if (AICompany.ResolveCompanyID(c) == AICompany.COMPANY_INVALID) continue;
		local value = AICompany.GetQuarterlyCompanyValue(c, 0);
		if (!found_rival || value > rival_value) {
			rival_value = value;
			found_rival = true;
		}
	}
	if (found_rival) {
		/* TODO: this should really compare against the *human* player specifically,
		 * not just whoever is richest - fine as a first pass while there's only
		 * ever one rival in dev testing. */
		if (rival_value > 0 && my_value < rival_value * 0.5) {
			candidates.push(Mood.UNDERDOG);
			weights.push(5.0);
		} else if (my_value > rival_value * 2) {
			candidates.push(Mood.SHOWMAN);
			weights.push(4.0);
		}
	}

	if (just_lost_money) {
		candidates.push(Mood.RECOVERY);
		weights.push(6.0);
	}

	/* TODO: also weight RIVAL up sharply when our route network and the
	 * player's overlap in the same towns/industries (needs a "who serves
	 * this industry" lookup once the route managers exist), and COPYCAT up
	 * when the player just did something visually distinctive (new vehicle
	 * type, new rail type, etc. - hook off AIEventController). */

	/* Try the remote decision service first: hand it the same candidates
	 * FunBrain.Choice() would pick from, described in words, and let it pick.
	 * Falls straight through to the local weighted-random choice on any
	 * failure (RemoteAvailable() false, server down, malformed reply, ...). */
	local criteria = {};
	foreach (mood in candidates) {
		criteria.rawset(MoodEngine.ToString(mood).tolower(), MoodEngine.Describe(mood));
	}
	local state = "Company value " + my_value + " vs. best rival's " + rival_value +
		" (no rival yet if 0). Just lost significant money: " + (just_lost_money ? "yes" : "no") + ".";
	local remote = SystemOne.Choice(state, "Which mood should this transport company adopt right now?", criteria);
	if (remote != null) {
		local chosen_name = remote[0];
		foreach (mood in candidates) {
			if (MoodEngine.ToString(mood).tolower() == chosen_name) {
				AILog.Info("Mood (remote, confidence " + remote[1] + "): " + MoodEngine.ToString(mood));
				this.current = mood;
				return this.current;
			}
		}
		/* Server picked something outside our candidate set - ignore it and fall through. */
	}

	this.current = FunBrain.Choice(candidates, weights);
	return this.current;
}

function MoodEngine::Describe(mood)
{
	switch (mood) {
		case Mood.SETTLER:  return "Neutral, still finding its feet, no strong read on the game yet";
		case Mood.UNDERDOG: return "Clearly behind the strongest rival: bold, cheap, catch-up plays";
		case Mood.RIVAL:    return "Competing head-on for the same towns/industries as the rival";
		case Mood.SHOWMAN:  return "Comfortably ahead: spend on spectacle instead of more optimal filler";
		case Mood.COPYCAT:  return "Mirror something the rival just did";
		case Mood.RECOVERY: return "Just took a big loss: visible panic-sell, then dramatic rebuild";
	}
	return "Unknown";
}

function MoodEngine::ToString(mood)
{
	switch (mood) {
		case Mood.SETTLER:  return "Settler";
		case Mood.UNDERDOG: return "Underdog";
		case Mood.RIVAL:    return "Rival";
		case Mood.SHOWMAN:  return "Showman";
		case Mood.COPYCAT:  return "Copycat";
		case Mood.RECOVERY: return "Recovery";
	}
	return "Unknown";
}
