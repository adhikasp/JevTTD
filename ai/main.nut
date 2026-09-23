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

/** @file main.nut Main loop. Currently just the event pump and mood
 * evaluation - the route managers that actually build anything are the
 * next piece of scaffolding (see README "Current scaffolding"). */

require("funbrain.nut");
require("mood.nut");

class JevTTD extends AIController {
	mood_engine = null;
	last_mood_logged = null;

	constructor()
	{
		::jev <- this;
		this.mood_engine = MoodEngine();
		this.last_mood_logged = null;
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
				 * and company-value events to the (not yet written) route
				 * managers once they exist. Vehicle crashes and big losses
				 * are also natural triggers for Mood.RECOVERY. */
			}
		}

		local mood = this.mood_engine.Evaluate();
		if (mood != this.last_mood_logged) {
			AILog.Info("Mood: " + MoodEngine.ToString(mood));
			this.last_mood_logged = mood;
		}

		/* TODO: this is where rail/road/air managers get consulted for a
		 * shortlist of candidate actions, which then goes through
		 * FunBrain.ScoreAndChoose(candidates, FunRubric, mood, pool_size)
		 * instead of a plain argmax. The rubric and managers are the next
		 * piece of scaffolding - see README. */

		AIController.Sleep(50);
	}
}
