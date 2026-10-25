---
-- LearnedAlert: a toast for every spell you learn; based on pretty_lootalert by s0h2x

local select = select;
local unpack = unpack;
local ipairs = ipairs;
local tonumber = tonumber;
local format = string.format;
local tRemove = table.remove;
local tInsert = table.insert;
local tWipe = table.wipe;

local private = select(2,...);
local config = private.config;
local mixin = private.Mixin;

-- /* config */
local scale = config.scale;
local offset_x = config.offset_x;
local point_x = config.point_x;
local point_y = config.point_y;
local uptime = config.time;
local spell_quality = config.spell_quality or 4;

local LEARNEDALERT_NUM_BUTTONS = math.max(1, math.min(config.numbuttons or 4, 8));

-- DragonUI (an OptionalDep, so it is loaded by now) gets the retail loot toast; everyone else the stock achievement alert
local SKINNED = _G.DragonUI ~= nil;

-- /* api's */
local PlaySoundFile = PlaySoundFile;
local GetSpellInfo = GetSpellInfo;
local GetSpellLink = GetSpellLink;
local GetSpellName = GetSpellName;
local GetSpellTexture = GetSpellTexture;
local GetNumCompanions = GetNumCompanions;
local GetCompanionInfo = GetCompanionInfo;
local GetTime = GetTime;
local GetRealmName = GetRealmName;
local UnitName = UnitName;
local GameTooltip = GameTooltip;

-- /* assets */
local assets = [[Interface\AddOns\LearnedAlert\assets\]];
local SOUND_SPELL_LEARNED = SKINNED and assets..(config.sound_file or "levelup.mp3") or [[Sound\Interface\LevelUp.wav]];
local FALLBACK_ICON = [[Interface\Icons\INV_Misc_Book_09]];

-- /* consts */
-- loot toast icon borders (DragonUI look); the stock look keeps the gold achievement icon frame
local BORDER_BY_QUALITY = {
	[2] = {0.34082, 0.397461, 0.53125, 0.644531},
	[3] = {0.272461, 0.329102, 0.785156, 0.898438},
	[4] = {0.34082, 0.397461, 0.882812, 0.996094},
	[5] = {0.34082, 0.397461, 0.765625, 0.878906},
	[6] = {0.272461, 0.329102, 0.667969, 0.78125},
	[7] = {0.34082, 0.397461, 0.648438, 0.761719},
};

-- /* patterns */
local PATTERNS_LEARN_SPELL = {};
for _, str in ipairs({ERR_LEARN_SPELL_S, ERR_LEARN_ABILITY_S, ERR_LEARN_PASSIVE_S}) do
	if str then
		tInsert(PATTERNS_LEARN_SPELL, "^"..str:gsub("([%.%(%)%-%+%*%?%[%]])", "%%%1"):gsub("%%s", "(.+)"));
	end
end

-- /* companions */
-- mounts and pets (the client's companion list), which get a toast of their own
local COMPANION_TYPES = {"MOUNT", "CRITTER"};
local COMPANION_LABELS = {MOUNT = LEARNEDALERT_NEW_MOUNT_LABEL, CRITTER = LEARNEDALERT_NEW_PET_LABEL};
local COMPANION_SCAN_DELAY = 2;	-- seconds after a loading screen, so the list is complete

-- this character's companions at the last scan, [type][spellID] = true; nil until the first scan
local companionsKnown;

-- /* tables */
local LearnedAlertFrameMixIn = {};
LearnedAlertFrameMixIn.alertQueue = {};
LearnedAlertFrameMixIn.alertButton = {};

function LearnedAlertFrameMixIn:AddAlert(name, link, texture, spellName, spellRank)
	tInsert(self.alertQueue, {
		name 		= name,
		link 		= link,
		texture 	= texture,
		spellName 	= spellName,
		spellRank 	= spellRank,
	});
end

-- name/rank lookups miss for ranked spells, so find the spell in the spellbook instead
local function FindInSpellBook(name, rank)
	local i = 1;
	while true do
		local bookName, bookRank = GetSpellName(i, BOOKTYPE_SPELL);
		if not bookName then return; end
		if bookName == name and (not rank or bookRank == rank) then
			return GetSpellLink(i, BOOKTYPE_SPELL), GetSpellTexture(i, BOOKTYPE_SPELL);
		end
		i = i + 1;
	end
end

-- fill in a missing link/icon; the spellbook may not have updated when the chat message arrived
local function ResolveSpell(data)
	if data.link or not data.spellName then return; end
	local link, icon = FindInSpellBook(data.spellName, data.spellRank);
	data.link = link;
	if icon and data.texture == FALLBACK_ICON then
		data.texture = icon;
	end
end

-- learned is either a spell link or plain text like "Frost Nova (Rank 1)"
function LearnedAlertFrameMixIn:AddSpell(learned)
	local spellID = tonumber(learned:match("|Hspell:(%d+)"));
	local text = learned:match("|h%[(.-)%]|h") or learned;
	local name, rank = text:match("^(.-)%s*%((.+)%)$");
	name = name or text;

	local icon, link, spellName = nil, nil, name;
	if spellID then
		local spellName, spellRank, spellIcon = GetSpellInfo(spellID);
		name = spellName or name;
		rank = (spellRank ~= "" and spellRank) or rank;
		icon = spellIcon;
		link = GetSpellLink(spellID);
	else
		-- lookups by name only work as "Name(Rank N)" or plain "Name"
		local query = rank and format("%s(%s)", name, rank) or name;
		local bookLink, bookIcon = FindInSpellBook(name, rank);
		icon = bookIcon or select(3, GetSpellInfo(query)) or select(3, GetSpellInfo(name));
		link = bookLink or GetSpellLink(query);
	end

	if rank then
		name = format("%s |cffffffff(%s)|r", name, rank);
	end
	self:AddAlert(name, link, icon or FALLBACK_ICON, spellName, rank);
end

-- the client announces these with ERR_LEARN_COMPANION_S, which the spell patterns don't match
function LearnedAlertFrameMixIn:AddCompanion(kind, name, spellID, icon)
	tInsert(self.alertQueue, {
		name 		= name or GetSpellInfo(spellID),
		link 		= GetSpellLink(spellID),
		texture 	= icon or FALLBACK_ICON,
		label 		= COMPANION_LABELS[kind],
		companion 	= kind,
	});
end

-- A mount or pet this account never had a toast for on this realm gets one: learned just now, or
-- added while you were logged out (the realm's shop sells them for the whole account, a gift). The
-- list is LearnedAlertSeenCompanions[realm], kept per realm because SavedVariables are shared by
-- every realm. A character's first scan adds what it has without toasts, so the first character to
-- log in can't leave the list empty for one that has more. One this character learns while
-- playing gets a toast even if another character had it already.
function LearnedAlertFrameMixIn:ScanCompanions()
	local saved = LearnedAlertSeenCompanions or {};
	LearnedAlertSeenCompanions = saved;
	local realm = GetRealmName();
	local seen = saved[realm] or {characters = {}};
	saved[realm] = seen;
	local character = UnitName("player");
	local quiet = not seen.characters[character];
	seen.characters[character] = true;

	local previous = companionsKnown;
	companionsKnown = {};

	for _, kind in ipairs(COMPANION_TYPES) do
		local seenKind = seen[kind] or {};
		seen[kind] = seenKind;
		local known = previous and previous[kind];
		local current = {};
		for i = 1, GetNumCompanions(kind) do
			local _, creatureName, spellID, icon = GetCompanionInfo(kind, i);
			if spellID then
				current[spellID] = true;
				if not quiet and (not seenKind[spellID] or (known and not known[spellID])) then
					self:AddCompanion(kind, creatureName, spellID, icon);
				end
				seenKind[spellID] = true;
			end
		end
		companionsKnown[kind] = current;
	end
end

function LearnedAlertFrameMixIn:CreateAlert()
	if #self.alertQueue > 0 then
		for i=1, LEARNEDALERT_NUM_BUTTONS do
			local button = self.alertButton[i];
			if button and not button:IsShown() then
				button.data = tRemove(self.alertQueue, 1);
				return button;
			end
		end
	end
	return nil;
end

function LearnedAlertFrameMixIn:AdjustAnchors()
	local previousButton;
	for i=1, LEARNEDALERT_NUM_BUTTONS do
		local button = self.alertButton[i];
		if button then
			button:ClearAllPoints();
			if button:IsShown() then
				if button.waitAndAnimOut:GetProgress() <= 0.74 then
					if not previousButton then
						if DungeonCompletionAlertFrame1:IsShown() then
							button:SetPoint("BOTTOM", DungeonCompletionAlertFrame1, "TOP", point_x, point_y);
						else
							button:SetPoint("CENTER", DungeonCompletionAlertFrame1, "CENTER", point_x, point_y);
						end
					else
						button:SetPoint("BOTTOM", previousButton, "TOP", 0, offset_x);
					end
				end
				previousButton = button;
			end
		end
	end
end

function LearnedAlertFrame_OnLoad(self)
	self.updateTime = uptime;

	self:RegisterEvent("CHAT_MSG_SYSTEM");
	self:RegisterEvent("PLAYER_ENTERING_WORLD");
	self:RegisterEvent("ACTIVE_TALENT_GROUP_CHANGED");
	self:RegisterEvent("COMPANION_LEARNED");

	mixin(self, LearnedAlertFrameMixIn);

	local template = SKINNED and "LearnedAlertLootToastTemplate" or "LearnedAlertButtonTemplate";
	for i=1, LEARNEDALERT_NUM_BUTTONS do
		CreateFrame("Button", "LearnedAlertButton"..i, UIParent, template);
	end
end

function LearnedAlertFrame_OnEvent(self, event, ...)
	-- dual spec swaps and loading screens re-announce known spells, so ignore those for a moment
	if event == "PLAYER_ENTERING_WORLD" or event == "ACTIVE_TALENT_GROUP_CHANGED" then
		self.spellMuteUntil = GetTime() + 5;
		if event == "PLAYER_ENTERING_WORLD" then
			self.companionScanAt = GetTime() + COMPANION_SCAN_DELAY;
		end
		return;
	end

	-- before the first scan the one after the loading screen finds it
	if event == "COMPANION_LEARNED" then
		if companionsKnown then
			LearnedAlertFrameMixIn:ScanCompanions();
		end
		return;
	end

	if event == "CHAT_MSG_SYSTEM" and GetTime() >= (self.spellMuteUntil or 0) then
		local message = ...;
		for _, pattern in ipairs(PATTERNS_LEARN_SPELL) do
			local learned = message:match(pattern);
			if learned then
				LearnedAlertFrameMixIn:AddSpell(learned);
				break;
			end
		end
	end
end

function LearnedAlertFrame_OnUpdate(self, elapsed)
	if self.companionScanAt and GetTime() >= self.companionScanAt then
		self.companionScanAt = nil;
		LearnedAlertFrameMixIn:ScanCompanions();
	end

	self.updateTime = self.updateTime - elapsed;
	if self.updateTime <= 0 then
		local alert = LearnedAlertFrameMixIn:CreateAlert();
		if alert then
			alert:SetScale(scale);
			alert:ClearAllPoints();
			alert:Show();
			alert.animIn:Play();
			LearnedAlertFrameMixIn:AdjustAnchors();
		end
		self.updateTime = uptime;
	end
end

function LearnedAlertButtonTemplate_OnLoad(self)
	self:RegisterForClicks("LeftButtonUp", "RightButtonUp");
	tInsert(LearnedAlertFrameMixIn.alertButton, self);
end

function LearnedAlertButtonTemplate_OnShow(self)
	local data = self.data;
	if not data or not data.name then
		self:Hide();
		return;
	end

	ResolveSpell(data);
	local qualityColor = ITEM_QUALITY_COLORS[spell_quality];

	self.Icon:SetTexture(data.texture);
	self.ItemName:SetText(data.name);
	self.Label:SetText(data.label or YOU_LEARNED_LABEL);

	if qualityColor then
		self.ItemName:SetTextColor(qualityColor.r, qualityColor.g, qualityColor.b);
	end
	if SKINNED and BORDER_BY_QUALITY[spell_quality] then
		self.IconBorder:SetTexCoord(unpack(BORDER_BY_QUALITY[spell_quality]));
	end

	-- several spells arrive at once on level up, so only play the sound once per batch
	if config.sound and GetTime() - (LearnedAlertFrameMixIn.lastSound or 0) > 3 then
		LearnedAlertFrameMixIn.lastSound = GetTime();
		PlaySoundFile(SOUND_SPELL_LEARNED);
	end

	if config.anims then
		self.glow.animIn:Play();
		self.shine.animIn:Play();
	end

	self.hyperLink = data.link;
	self.companionType = data.companion;
end

local function GetButtonLink(self)
	if not self.hyperLink and self.data then
		ResolveSpell(self.data);
		self.hyperLink = self.data.link;
	end
	return self.hyperLink;
end

function LearnedAlertButtonTemplate_OnHide(self)
	self.animIn:Stop();
	self.waitAndAnimOut:Stop();

	if config.anims then
		self.glow.animIn:Stop();
		self.shine.animIn:Stop();
	end

	if self.data then
		tWipe(self.data);
	end
	LearnedAlertFrameMixIn:AdjustAnchors();
end

-- DragonUI's Pets & Mounts window when it has one, else the stock companion tabs of the character
-- frame; opened on that tab, never toggled, so a click can't close a window that's already open
local function OpenCompanions(kind)
	local collections = SKINNED and _G.DragonUI.Collections;
	local microButton = _G.CollectionsMicroButton;
	if collections and collections.Open and microButton and not microButton.dragonUISuppressed then
		collections.Open(kind);
		if collections.SelectKind then
			collections.SelectKind(kind);
		end
		return;
	end
	if not PetPaperDollFrame:IsVisible() then
		ToggleCharacter("PetPaperDollFrame");
	end
	PetPaperDollFrame_SetTab(kind == "MOUNT" and 3 or 2);
end

function LearnedAlertButtonTemplate_OnClick(self, button)
	if button == "RightButton" then
		self:Hide();
	elseif self.companionType and not IsModifierKeyDown() then
		OpenCompanions(self.companionType);
	elseif GetButtonLink(self) then
		HandleModifiedItemClick(self.hyperLink);
	end
end

function LearnedAlertButtonTemplate_OnEnter(self)
	if not GetButtonLink(self) then return; end
	GameTooltip:SetOwner(self, "ANCHOR_RIGHT", -14, -6);
	GameTooltip:SetHyperlink(self.hyperLink);
	GameTooltip:Show();
end

-- /learned test: fakes the chat message for a spell you know, so the toast can be checked anytime;
-- /learned test mount (or pet): the toast for your first mount (or pet)
SLASH_LEARNEDALERT1 = "/learned";
SLASH_LEARNEDALERT2 = "/levelup";  -- the old pretty_levelup command
SlashCmdList["LEARNEDALERT"] = function(msg)
	if msg == "test" then
		local name, rank = GetSpellInfo(6603); -- Attack, every class has it
		local sample = (rank and rank ~= "") and format("%s (%s)", name, rank) or name;
		LearnedAlertFrameMixIn:AddSpell(sample);
	elseif msg == "test mount" or msg == "test pet" then
		local kind = (msg == "test mount") and "MOUNT" or "CRITTER";
		local _, creatureName, spellID, icon = GetCompanionInfo(kind, 1);
		if spellID then
			LearnedAlertFrameMixIn:AddCompanion(kind, creatureName, spellID, icon);
		else
			print(format("LearnedAlert: you have no %s to show", kind == "MOUNT" and "mount" or "pet"));
		end
	else
		print("LearnedAlert: /learned test - show a sample toast; /learned test mount, /learned test pet - the mount and pet toasts");
	end
end
