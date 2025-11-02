--[[	file meta info
	@file 		WhatsTraining.lua
	@brief		Main script
--]]

--[[
	@brief		Accessing the addons private table

	@var 	addonName		addonName from ToC
	@var	wt				Global addonTable
--]]
local addonName, wt = ...

-- Check for ClassTrainerPlus integration
local ignoreStore = LibStub and LibStub:GetLibrary("FusionIgnoreStore-1.0", true)

-- @brief		"Constant" variables
local AVAILABLE_KEY =					"available"
local MISSINGREQS_KEY =					"missingReqs"
local NEXTLEVEL_KEY =					"nextLevel"
local NOTLEVEL_KEY =					"notLevel"
local MISSINGTALENT_KEY =				"missingTalent"
local KNOWN_KEY =						"known"
local IGNORED_KEY =						"ignored"
local COMINGSOON_FONT_COLOR_CODE =		"|cff82c5ff"
local MISSINGTALENT_FONT_COLOR_CODE =	"|cffffffff"
local IGNORED_FONT_COLOR_CODE =			"|cffffd100"

local function isMountLearned(spellId)
	local numMounts = GetNumCompanions("MOUNT")
	if numMounts == 0 then
		return
	else
		local mountSpellId
		for i = 1, numMounts do
			mountSpellId = select(3, GetCompanionInfo("MOUNT", i))
			if mountSpellId == spellId then
				return true
			end
		end
	end
end

local function isPreviouslyLearnedAbility(spellId)
	if (wt.overriddenSpellsMap == nil or not wt.overriddenSpellsMap[spellId]) then
		return false
	end
	local spellIndex, knownIndex = 0, 0
	for i, otherId in ipairs(wt.overriddenSpellsMap[spellId]) do
		if (otherId == spellId) then spellIndex = i end
		--if (IsSpellKnown(otherId) or IsPlayerSpell(otherId)) then
		if (IsSpellKnown(otherId) or isMountLearned(otherId)) then
			knownIndex = i
		end
	end
	return spellIndex <= knownIndex
end

local function isAbilityKnown(spellId)
	if (IsSpellKnown(spellId) or
		isMountLearned(spellId) or
		--IsPlayerSpell(spellId) or
		isPreviouslyLearnedAbility(spellId)) then
		return true
	end
end

local headers = {
	{
		name = wt.L.AVAILABLE_HEADER,
		color = GREEN_FONT_COLOR_CODE,
		hideLevel = true,
		key = AVAILABLE_KEY
	}, {
		name = wt.L.MISSINGREQS_HEADER,
		color = ORANGE_FONT_COLOR_CODE,
		hideLevel = true,
		key = MISSINGREQS_KEY
	}, {
		name = wt.L.NEXTLEVEL_HEADER,
		color = COMINGSOON_FONT_COLOR_CODE,
		key = NEXTLEVEL_KEY
	},{
		name = wt.L.NOTLEVEL_HEADER,
		color = RED_FONT_COLOR_CODE,
		key = NOTLEVEL_KEY
	},{
		name = wt.L.MISSINGTALENT_HEADER,
		color = MISSINGTALENT_FONT_COLOR_CODE,
		key = MISSINGTALENT_KEY
	},{
		name = wt.L.KNOWN_HEADER,
		color = GRAY_FONT_COLOR_CODE,
		hideLevel = true,
		key = KNOWN_KEY,
		nameSort = true
	},{
		name = "Ignored",
		color = IGNORED_FONT_COLOR_CODE,
		key = IGNORED_KEY,
		nameSort = true,
		requiresIntegration = true
	},
}

local categories = {
	_spellsByCategoryKey = {},
	Insert = function(self, key, spellInfo)
		tinsert(self._spellsByCategoryKey[key], spellInfo)
	end,
	Initialize = function(self)
		for _, cat in ipairs(headers) do
			-- Skip ignored category if ClassTrainerPlus isn't present
			if not (cat.requiresIntegration and not ignoreStore) then
				cat.spells = {}
				self._spellsByCategoryKey[cat.key] = cat.spells
				cat.formattedName = cat.color .. cat.name .. FONT_COLOR_CODE_CLOSE
				cat.isHeader = true
				tinsert(self, cat)
			end
		end
	end,
	ClearSpells = function(self)
		for _, cat in ipairs(self) do
			cat.cost = 0
			wipe(cat.spells)
		end
	end
}
categories:Initialize()

wt.data = {}
local function rebuildData(playerLevel, isLevelUpEvent)
	categories:ClearSpells()
	wipe(wt.data)
	
	-- Get search filter if any
	local searchFilter = wt.searchFilter
	
	for level, spellsAtLevel in pairs(wt.SpellsByLevel) do
		for _, spell in ipairs(spellsAtLevel) do
			local spellInfo = wt:SpellInfo(spell.id)
			if (spellInfo ~= nil) then
				-- Apply search filter
				local matchesSearch = true
				if searchFilter then
					matchesSearch = spellInfo.name:lower():find(searchFilter, 1, true) ~= nil
				end
				
				if matchesSearch then
					local categoryKey
					
					-- Check if spell is ignored (ClassTrainerPlus integration)
					local isIgnored = ignoreStore and ignoreStore:IsIgnored(spellInfo.id)

				if (isIgnored) then
					categoryKey = IGNORED_KEY
				elseif (isAbilityKnown(spellInfo.id)) then
					categoryKey = KNOWN_KEY
				elseif (spell.requiredTalentId ~= nil and
					not isAbilityKnown(spell.requiredTalentId)) then
					categoryKey = MISSINGTALENT_KEY
				elseif (level > playerLevel) then
					categoryKey = level <= playerLevel + 2 and NEXTLEVEL_KEY or
									  NOTLEVEL_KEY
				else
					local hasReqs = true
					if (spell.requiredIds ~= nil) then
						for _, reqId in ipairs(spell.requiredIds) do
							hasReqs = hasReqs and isAbilityKnown(reqId)
						end
					end
					categoryKey = hasReqs and AVAILABLE_KEY or MISSINGREQS_KEY
				end
				if (categoryKey ~= nil) then
					categories:Insert(categoryKey, spellInfo)
				end
				end -- end matchesSearch
			end
		end
	end

	local function byLevelThenName(a, b)
		if (a.level == b.level) then
			return a.name < b.name
		end
		return a.level < b.level
	end
	local function byNameThenLevel(a, b)
		if (a.name == b.name) then
			return a.level < b.level
		end
		return a.name < b.name
	end
	for _, category in ipairs(categories) do
		if (#category.spells > 0) then
			tinsert(wt.data, category)
			local sortFunc = category.nameSort and byNameThenLevel or
								 byLevelThenName
			sort(category.spells, sortFunc)
			local totalCost = 0
			for _, s in ipairs(category.spells) do
				local effectiveLevel = s.level
				-- when a player levels up and this is triggered from that event, GetQuestDifficultyColor won't
				-- have the correct player level, it will be off by 1 for whatever reason (just like UnitLevel)
				if (isLevelUpEvent) then
					effectiveLevel = effectiveLevel - 1
				end
				s.levelColor = GetQuestDifficultyColor(effectiveLevel)
				s.hideLevel = category.hideLevel
				totalCost = totalCost + s.cost
				tinsert(wt.data, s)
			end
			category.cost = totalCost
		end
	end
	if (wt.MainFrame == nil) then return end
end

local function rebuildIfNotCached(fromCache)
	if (fromCache or wt.MainFrame == nil) then return end
	rebuildData(UnitLevel("player"))
end

function wt:RebuildData()
	rebuildData(UnitLevel("player"))
	if (self.MainFrame and self.MainFrame:IsVisible()) then
		self.Update(self.MainFrame, true)
	end
end

for level, spellsByLevel in pairs(wt.SpellsByLevel) do
	for _, spell in ipairs(spellsByLevel) do
		wt:CacheSpell(spell, level, rebuildIfNotCached)
	end
end

-- Subscribe to ClassTrainerPlus ignore list changes
if ignoreStore then
	ignoreStore:AddSubscription(function()
		wt:RebuildData()
	end)
	
	-- Set up right-click hook to toggle ignore
	wt.ClickHook = function(spellId, callback)
		local spellIds = {spellId}
		
		-- If shift is held, get all ranks of this spell
		local shiftDown = IsShiftKeyDown()
		if shiftDown then
			-- Try to use overriddenSpellsMap if available
			if wt.overriddenSpellsMap and wt.overriddenSpellsMap[spellId] then
				spellIds = wt.overriddenSpellsMap[spellId]
			else
				-- Fallback: Find all spells with the same base name
				local currentSpellName = GetSpellInfo(spellId)
				if currentSpellName then
					-- Remove rank info to get base name (e.g., "Corruption (Rank 3)" -> "Corruption")
					local baseName = currentSpellName:match("^(.-)%s*%(") or currentSpellName
					spellIds = {}
					-- Search through all spells to find matching base names
					for level, spellsAtLevel in pairs(wt.SpellsByLevel) do
						for _, spell in ipairs(spellsAtLevel) do
							local name = GetSpellInfo(spell.id)
							if name then
								local checkBaseName = name:match("^(.-)%s*%(") or name
								if checkBaseName == baseName then
									tinsert(spellIds, spell.id)
								end
							end
						end
					end
				end
			end
		end
		
		-- Check if all spells are currently ignored to determine toggle direction
		local allIgnored = true
		for _, id in ipairs(spellIds) do
			if not ignoreStore:IsIgnored(id) then
				allIgnored = false
				break
			end
		end
		
		-- Toggle all spell IDs (if shift held, toggles all ranks; otherwise just the one)
		ignoreStore:UpdateMany(spellIds, not allIgnored)
		
		if callback then callback() end
	end
end

local eventFrame = CreateFrame("Frame")
eventFrame:SetScript("OnEvent", function(self, event, ...)
	if (event == "PLAYER_ENTERING_WORLD") then
		local isLogin, isReload = ...
		--if (isLogin or isReload) then
		rebuildData(UnitLevel("player"))
		wt.CreateFrame()
		--end
	elseif (event == "LEARNED_SPELL_IN_TAB" or event == "PLAYER_LEVEL_UP") then
		local isLevelUp = event == "PLAYER_LEVEL_UP"
		rebuildData(isLevelUp and ... or UnitLevel("player"), isLevelUp)
		if (wt.MainFrame and wt.MainFrame:IsVisible()) then
			wt.Update(wt.MainFrame, true)
		end
	end
end)

eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("LEARNED_SPELL_IN_TAB")
eventFrame:RegisterEvent("PLAYER_LEVEL_UP")
