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

/** @file main.nut Main loop: event pump, mood evaluation, and (so far) one
 * working route manager - see air/aircraftmanager.nut. Rail/road managers
 * are the next piece of scaffolding (see README "Current scaffolding"). */

require("json.nut");
require("funbrain.nut");
require("systemone.nut");
require("mood.nut");
require("air/aircraftmanager.nut");

class JevTTD extends AIController {
	mood_engine = null;
	aircraft_manager = null;
	last_mood_logged = null;
	last_route_attempt = null;
	last_finance_log = null;

	constructor()
	{
		::jev <- this;
		this.mood_engine = MoodEngine();
		this.aircraft_manager = AircraftManager();
		this.last_mood_logged = null;
		this.last_route_attempt = 0;
		this.last_finance_log = 0;
	}

	function Start();
}

function JevTTD::Start()
{
	local name = "JevTTD";
	local suffix = 0;
	while (!AICompany.SetName(suffix == 0 ? name : (name + " #" + suffix))) {
		suffix++;
	}
	AILog.Info(AICompany.GetName(AICompany.COMPANY_SELF) + " has started. Playing for the story, not the spreadsheet.");

	while (true) {
		while (AIEventController.IsEventWaiting()) {
			local e = AIEventController.GetNextEvent();
			switch (e.GetEventType()) {
				case AIEvent.ET_ENGINE_PREVIEW:
					AIEventEnginePreview.Convert(e).AcceptPreview();
					break;
				/* TODO: route AI_ET_INDUSTRY_OPEN / _CLOSE, vehicle crashes,
				 * and company-value events to the route managers. Vehicle
				 * crashes and big losses are also natural triggers for
				 * Mood.RECOVERY. */
			}
		}

		local mood = this.mood_engine.Evaluate();
		if (mood != this.last_mood_logged) {
			AILog.Info("Mood: " + MoodEngine.ToString(mood));
			this.last_mood_logged = mood;
		}

		/* TODO: once there's more than one manager, candidate actions from
		 * all of them should go through FunBrain.ScoreAndChoose(candidates,
		 * FunRubric, mood, pool_size) instead of just always asking the one
		 * manager we have. For now there is exactly one thing to do. */
		local today = AIDate.GetCurrentDate();
		if (today - this.last_route_attempt >= 60) {
			this.last_route_attempt = today;
			this.aircraft_manager.BuildNewRoute();
		}

		if (today - this.last_finance_log >= 90) {
			this.last_finance_log = today;
			AILog.Info("Finances: bank=" + AICompany.GetBankBalance(AICompany.COMPANY_SELF) +
				" loan=" + AICompany.GetLoanAmount() +
				" value=" + AICompany.GetQuarterlyCompanyValue(AICompany.COMPANY_SELF, 0) +
				" vehicles=" + AIVehicleList().Count());
		}

		AIController.Sleep(50);
	}
}
