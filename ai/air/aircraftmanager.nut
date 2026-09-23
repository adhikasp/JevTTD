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
 * @file air/aircraftmanager.nut First real, working route builder: small
 * airports + small planes between two towns. Aircraft chosen deliberately
 * for v1 - unlike road/rail, planes need no pathfinding or junction/signal
 * logic, just two buildable patches of ground, so this is the fastest path
 * to "JevTTD actually earns money" without a custom pathfinder.
 *
 * Where AdmiralAI/trAIns pick the *provably best* route, this picks *a
 * decent* route with FunBrain.Choice() - population-weighted-random town
 * selection instead of always the two biggest towns on the map. The
 * mechanics (tile search, airport/plane building) are otherwise the
 * standard AdmiralAI-style approach, since that part isn't where "fun vs.
 * optimal" lives - see the FunBrain.Choice() calls below for where it does.
 */

class AircraftManager {
	engine_id = null;
	passenger_cargo = null;

	constructor()
	{
		this.engine_id = null;
		this.passenger_cargo = null;
	}

	function GetPassengerCargo();
	function EnsureMoney(amount);
	function AvailableCapital();
	function FindEngine();
	static function EngineValue(engine_id);
	function FindAirportTile(town_id);
	function BuildNewRoute();
	function BuildPlanes(station_a, station_b);
}

function AircraftManager::GetPassengerCargo()
{
	if (this.passenger_cargo != null) return this.passenger_cargo;

	local list = AICargoList();
	list.Valuate(AICargo.HasCargoClass, AICargo.CC_PASSENGERS);
	list.KeepValue(1);
	if (list.IsEmpty()) return null;
	this.passenger_cargo = list.Begin();
	return this.passenger_cargo;
}

function AircraftManager::EnsureMoney(amount)
{
	local bank = AICompany.GetBankBalance(AICompany.COMPANY_SELF);
	if (bank >= amount) return;
	local wanted_loan = AICompany.GetLoanAmount() + (amount - bank);
	AICompany.SetLoanAmount(min(AICompany.GetMaxLoanAmount(), wanted_loan));
}

/**
 * Cash on hand plus remaining loan headroom - the true ceiling on what we
 * can spend right now, as opposed to EnsureMoney(), which can silently ask
 * for more than the bank will ever lend.
 */
function AircraftManager::AvailableCapital()
{
	return AICompany.GetBankBalance(AICompany.COMPANY_SELF) +
		(AICompany.GetMaxLoanAmount() - AICompany.GetLoanAmount());
}

/* static */ function AircraftManager::EngineValue(engine_id)
{
	return AIEngine.GetCapacity(engine_id) * AIEngine.GetMaxSpeed(engine_id);
}

function AircraftManager::FindEngine()
{
	local list = AIEngineList(AIVehicle.VT_AIR);
	list.Valuate(AIEngine.GetPlaneType);
	list.KeepValue(AIAirport.PT_SMALL_PLANE);
	if (list.IsEmpty()) return false;

	list.Valuate(AircraftManager.EngineValue);
	list.Sort(AIList.SORT_BY_VALUE, AIList.SORT_DESCENDING);
	this.engine_id = list.Begin();
	return true;
}

function AircraftManager::FindAirportTile(town_id)
{
	local type = AIAirport.AT_SMALL;
	local cargo = this.GetPassengerCargo();
	if (cargo == null) return null;

	local w = AIAirport.GetAirportWidth(type);
	local h = AIAirport.GetAirportHeight(type);
	local radius = AIAirport.GetAirportCoverageRadius(type);
	local center = AITown.GetLocation(town_id);
	local cx = AIMap.GetTileX(center);
	local cy = AIMap.GetTileY(center);
	local span = 20;
	local x0 = max(1, cx - span);
	local y0 = max(1, cy - span);
	local x1 = min(AIMap.GetMapSizeX() - 2, cx + span);
	local y1 = min(AIMap.GetMapSizeY() - 2, cy + span);

	local tiles = AITileList();
	tiles.AddRectangle(AIMap.GetTileIndex(x0, y0), AIMap.GetTileIndex(x1, y1));
	tiles.Valuate(AITile.GetCargoAcceptance, cargo, w, h, radius);
	tiles.KeepAboveValue(30);
	if (tiles.IsEmpty()) return null;
	tiles.Valuate(AIAirport.GetNoiseLevelIncrease, type);
	tiles.KeepBelowValue(AITown.GetAllowedNoise(town_id) + 1);
	if (tiles.IsEmpty()) return null;
	tiles.Valuate(AIMap.DistanceSquare, center);
	tiles.Sort(AIList.SORT_BY_VALUE, AIList.SORT_ASCENDING);

	/* No terraforming (v1 keeps it simple) - just try a lot of candidates.
	 * Near-center tiles are often too hilly/built-up for a flat 4x3 airport
	 * footprint, so a small budget here (e.g. 40) fails far more often than
	 * it should; 200 empirically finds a spot in practice. */
	local tried = 0;
	local max_tries = min(200, tiles.Count());
	foreach (tile, dummy in tiles) {
		if (tried >= max_tries) break;
		tried++;
		local built = false;
		{
			local test = AITestMode();
			built = AIAirport.BuildAirport(tile, type, AIStation.STATION_NEW);
		}
		if (built) return tile;
	}
	return null;
}

function AircraftManager::BuildNewRoute()
{
	if (this.engine_id == null || !AIEngine.IsBuildable(this.engine_id)) {
		if (!this.FindEngine()) return false;
	}

	/* Cheap early-out before spending time scanning towns/tiles: if we
	 * couldn't even in principle afford a route right now, don't bother. */
	local rough_cost = 2 * AIAirport.GetPrice(AIAirport.AT_SMALL) + 2 * AIEngine.GetPrice(this.engine_id) + 10000;
	if (this.AvailableCapital() < rough_cost) return false;

	local town_list = AITownList();
	town_list.Valuate(AITown.GetPopulation);
	town_list.KeepAboveValue(300);
	if (town_list.Count() < 2) return false;

	local towns = [];
	foreach (t, pop in town_list) towns.push(t);

	/* Population-weighted-random pick, not "always the biggest town" - the
	 * one place in this file that's actually FunBrain's call rather than a
	 * plain greedy heuristic. */
	local weights_a = [];
	foreach (t in towns) weights_a.push(AITown.GetPopulation(t).tofloat());
	local town_a = FunBrain.Choice(towns, weights_a);

	local candidates_b = [];
	local weights_b = [];
	foreach (t in towns) {
		if (t == town_a) continue;
		local dist = AIMap.DistanceManhattan(AITown.GetLocation(town_a), AITown.GetLocation(t));
		if (dist < 40 || dist > 300) continue;
		candidates_b.push(t);
		weights_b.push(AITown.GetPopulation(t).tofloat());
	}
	if (candidates_b.len() == 0) return false;
	local town_b = FunBrain.Choice(candidates_b, weights_b);

	/* Full up-front cost check, before touching any money: two small
	 * airports plus two planes. Without this, a route that's affordable at
	 * the airport-building step but not by the time we reach the vehicle
	 * step leaves behind unprofitable, un-served airports quietly bleeding
	 * money every period - that's what was happening before this check
	 * existed (found by actually running the AI and watching bank balance
	 * go negative while stuck at 2 vehicles). */
	local total_cost = 2 * AIAirport.GetPrice(AIAirport.AT_SMALL) + 2 * AIEngine.GetPrice(this.engine_id) + 10000;
	if (this.AvailableCapital() < total_cost) return false;

	local tile_a = this.FindAirportTile(town_a);
	if (tile_a == null) return false;
	local tile_b = this.FindAirportTile(town_b);
	if (tile_b == null) return false;

	this.EnsureMoney(total_cost);
	if (!AIAirport.BuildAirport(tile_a, AIAirport.AT_SMALL, AIStation.STATION_NEW)) {
		AILog.Warning("Airport build failed at town A: " + AIError.GetLastErrorString());
		return false;
	}
	local station_a = AIStation.GetStationID(tile_a);

	if (!AIAirport.BuildAirport(tile_b, AIAirport.AT_SMALL, AIStation.STATION_NEW)) {
		AILog.Warning("Airport build failed at town B: " + AIError.GetLastErrorString());
		AITile.DemolishTile(tile_a);
		return false;
	}
	local station_b = AIStation.GetStationID(tile_b);

	if (this.BuildPlanes(station_a, station_b)) return true;

	/* No vehicles ended up serving either airport - tear both down rather
	 * than leave a pure cost sink behind. */
	AITile.DemolishTile(tile_a);
	AITile.DemolishTile(tile_b);
	return false;
}

function AircraftManager::BuildPlanes(station_a, station_b)
{
	this.EnsureMoney(2 * AIEngine.GetPrice(this.engine_id) + 20000);

	local hangar_a = AIAirport.GetHangarOfAirport(AIStation.GetLocation(station_a));
	local v = AIVehicle.BuildVehicle(hangar_a, this.engine_id);
	if (!AIVehicle.IsValidVehicle(v)) {
		AILog.Warning("Building plane failed: " + AIError.GetLastErrorString());
		return false;
	}
	AIOrder.AppendOrder(v, AIStation.GetLocation(station_a), AIOrder.OF_NONE);
	AIOrder.AppendOrder(v, AIStation.GetLocation(station_b), AIOrder.OF_NONE);
	AIVehicle.StartStopVehicle(v);

	local hangar_b = AIAirport.GetHangarOfAirport(AIStation.GetLocation(station_b));
	local v2 = AIVehicle.CloneVehicle(hangar_b, v, false);
	if (AIVehicle.IsValidVehicle(v2)) {
		AIOrder.SkipToOrder(v2, 1);
		AIVehicle.StartStopVehicle(v2);
	}

	AILog.Info("New air route: " + AIStation.GetName(station_a) + " <-> " + AIStation.GetName(station_b));
	return true;
}
