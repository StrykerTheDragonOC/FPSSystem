-- WeaponManager.lua
-- Server-side weapon management system that handles all weapons
-- Place in ServerScriptService.FPSSystem

local WeaponManager = {}

-- Services
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")
local Players = game:GetService("Players")
local Teams = game:GetService("Teams")
local RunService = game:GetService("RunService")
local PhysicsService = game:GetService("PhysicsService")

-- Constants
local DEFAULT_WEAPONS = {
	PRIMARY = "G36",
	SECONDARY = "Pistol",
	MELEE = "Knife",
	TACTICAL = "Smoke",
	LETHAL = "Grenade"
}

-- Player data structure
local playerWeapons = {}
local playerStates = {}

-- Remote events
local remoteEvents = {}

-- Initialize weapon manager
function WeaponManager:Initialize()
	print("Initializing WeaponManager...")

	-- Make sure folders exist
	self:EnsureFolders()

	-- Setup remote events
	self:SetupRemoteEvents()

	-- Register collision groups
	self:SetupCollisionGroups()

	-- Load weapon configurations
	self:LoadWeaponConfigs()

	-- Connect to player events
	Players.PlayerAdded:Connect(function(player)
		self:SetupPlayer(player)
	end)

	Players.PlayerRemoving:Connect(function(player)
		self:CleanupPlayer(player)
	end)

	-- Connect existing players
	for _, player in ipairs(Players:GetPlayers()) do
		task.spawn(function()
			self:SetupPlayer(player)
		end)
	end

	print("WeaponManager initialized!")
end

-- Ensure all necessary folders exist
function WeaponManager:EnsureFolders()
	-- Create folders in ReplicatedStorage
	local fpsSystem = ReplicatedStorage:FindFirstChild("FPSSystem")
	if not fpsSystem then
		fpsSystem = Instance.new("Folder")
		fpsSystem.Name = "FPSSystem"
		fpsSystem.Parent = ReplicatedStorage
	end

	local remoteEvents = fpsSystem:FindFirstChild("RemoteEvents")
	if not remoteEvents then
		remoteEvents = Instance.new("Folder")
		remoteEvents.Name = "RemoteEvents"
		remoteEvents.Parent = fpsSystem
	end

	local modules = fpsSystem:FindFirstChild("Modules")
	if not modules then
		modules = Instance.new("Folder")
		modules.Name = "Modules"
		modules.Parent = fpsSystem
	end

	local config = fpsSystem:FindFirstChild("Config")
	if not config then
		config = Instance.new("Folder")
		config.Name = "Config"
		config.Parent = fpsSystem
	end

	-- Create folders in ServerStorage
	local serverStorage = ServerStorage:FindFirstChild("FPSSystem")
	if not serverStorage then
		serverStorage = Instance.new("Folder")
		serverStorage.Name = "FPSSystem"
		serverStorage.Parent = ServerStorage
	end

	local serverConfig = serverStorage:FindFirstChild("Config")
	if not serverConfig then
		serverConfig = Instance.new("Folder")
		serverConfig.Name = "Config"
		serverConfig.Parent = serverStorage
	end
end

-- Setup remote events
function WeaponManager:SetupRemoteEvents()
	local eventsFolder = ReplicatedStorage:FindFirstChild("FPSSystem"):FindFirstChild("RemoteEvents")

	-- Define all events we need
	local eventsList = {
		"WeaponEquip",     -- Client equips a weapon
		"WeaponFired",     -- Client fires a weapon
		"HitRegistration", -- Client registers a hit
		"WeaponReload",    -- Client reloads a weapon
		"WeaponState",     -- Client changes weapon state
		"GrenadeEvent",    -- Client throws a grenade
		"MeleeEvent",      -- Client swings melee weapon
		"WeaponData"       -- Client requests weapon data
	}

	-- Create or get each event
	for _, eventName in ipairs(eventsList) do
		local event = eventsFolder:FindFirstChild(eventName)
		if not event then
			event = Instance.new("RemoteEvent")
			event.Name = eventName
			event.Parent = eventsFolder
		end

		remoteEvents[eventName] = event
	end

	-- Connect to events
	remoteEvents.WeaponEquip.OnServerEvent:Connect(function(player, weaponName, slot)
		self:HandleWeaponEquip(player, weaponName, slot)
	end)

	remoteEvents.WeaponFired.OnServerEvent:Connect(function(player, weaponName, bulletData)
		self:HandleWeaponFired(player, weaponName, bulletData)
	end)

	remoteEvents.HitRegistration.OnServerEvent:Connect(function(player, hitCharacter, hitData)
		self:HandleHitRegistration(player, hitCharacter, hitData)
	end)

	remoteEvents.WeaponReload.OnServerEvent:Connect(function(player, weaponName)
		self:HandleWeaponReload(player, weaponName)
	end)

	remoteEvents.WeaponState.OnServerEvent:Connect(function(player, state)
		self:HandleWeaponState(player, state)
	end)

	remoteEvents.GrenadeEvent.OnServerEvent:Connect(function(player, action, data)
		self:HandleGrenadeEvent(player, action, data)
	end)

	remoteEvents.MeleeEvent.OnServerEvent:Connect(function(player, action, data)
		self:HandleMeleeEvent(player, action, data)
	end)

	remoteEvents.WeaponData.OnServerEvent:Connect(function(player, action, data)
		self:HandleWeaponData(player, action, data)
	end)
end

-- Setup collision groups
function WeaponManager:SetupCollisionGroups()
	-- Using PhysicsService
	pcall(function()
		-- Register collision groups
		PhysicsService:RegisterCollisionGroup("Players")
		PhysicsService:RegisterCollisionGroup("WeaponHitboxes")
		PhysicsService:RegisterCollisionGroup("Bullets")
		PhysicsService:RegisterCollisionGroup("Grenades")

		-- Configure collision rules
		PhysicsService:CollisionGroupSetCollidable("Players", "Players", false)
		PhysicsService:CollisionGroupSetCollidable("Players", "WeaponHitboxes", true)
		PhysicsService:CollisionGroupSetCollidable("Players", "Bullets", true)
		PhysicsService:CollisionGroupSetCollidable("Players", "Grenades", true)

		PhysicsService:CollisionGroupSetCollidable("WeaponHitboxes", "WeaponHitboxes", false)
		PhysicsService:CollisionGroupSetCollidable("Bullets", "Bullets", false)
	end)
end

-- Load weapon configurations
function WeaponManager:LoadWeaponConfigs()
	-- Try to require WeaponConfig module
	local success, WeaponConfig = pcall(function()
		return require(ReplicatedStorage.FPSSystem.Modules.WeaponConfig)
	end)

	if success and WeaponConfig then
		self.weaponConfigs = WeaponConfig.Weapons
		print("Loaded " .. (self.weaponConfigs and #self.weaponConfigs or 0) .. " weapon configurations")
	else
		warn("Failed to load WeaponConfig module. Using default configurations.")
		self.weaponConfigs = {}
	end
end

-- Set up a player's weapons
function WeaponManager:SetupPlayer(player)
	print("Setting up weapons for player: " .. player.Name)

	-- Initialize player data
	playerWeapons[player.UserId] = {}
	playerStates[player.UserId] = {
		currentWeapon = nil,
		currentSlot = nil,
		state = "IDLE"
	}

	-- Load default weapons
	for slot, weaponName in pairs(DEFAULT_WEAPONS) do
		self:GiveWeapon(player, weaponName, slot)
	end

	-- Set up character when spawned
	player.CharacterAdded:Connect(function(character)
		self:SetupCharacter(player, character)
	end)

	-- Set up existing character if player already has one
	if player.Character then
		self:SetupCharacter(player, player.Character)
	end
end

-- Set up a player's character
function WeaponManager:SetupCharacter(player, character)
	print("Setting up character for player: " .. player.Name)

	-- Set collision group
	for _, part in ipairs(character:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CollisionGroup = "Players"
		end
	end

	-- Handle character death
	local humanoid = character:WaitForChild("Humanoid")
	humanoid.Died:Connect(function()
		print("Player died: " .. player.Name)
		-- Handle death - reset weapon states
		playerStates[player.UserId] = {
			currentWeapon = nil,
			currentSlot = nil,
			state = "IDLE"
		}
	end)
end

-- Cleanup player data
function WeaponManager:CleanupPlayer(player)
	playerWeapons[player.UserId] = nil
	playerStates[player.UserId] = nil
end

-- Give a weapon to a player
function WeaponManager:GiveWeapon(player, weaponName, slot)
	-- Make sure player data exists
	if not playerWeapons[player.UserId] then
		playerWeapons[player.UserId] = {}
	end

	-- Get weapon configuration
	local weaponConfig = self:GetWeaponConfig(weaponName)

	-- Create weapon instance
	local weaponInstance = {
		name = weaponName,
		config = weaponConfig,
		slot = slot,
		ammo = {
			current = weaponConfig.magazine and weaponConfig.magazine.size or 30,
			reserve = weaponConfig.magazine and weaponConfig.magazine.maxAmmo or 120,
			maxSize = weaponConfig.magazine and weaponConfig.magazine.size or 30
		},
		attachments = {}
	}

	-- Store in player's weapons
	playerWeapons[player.UserId][slot] = weaponInstance

	print("Gave weapon " .. weaponName .. " to player " .. player.Name .. " in slot " .. slot)

	return weaponInstance
end

-- Get a weapon configuration
function WeaponManager:GetWeaponConfig(weaponName)
	-- Check if we have loaded configs
	if self.weaponConfigs and self.weaponConfigs[weaponName] then
		return self.weaponConfigs[weaponName]
	end

	-- Otherwise create a default config
	return self:CreateDefaultConfig(weaponName)
end

-- Create a default weapon configuration
function WeaponManager:CreateDefaultConfig(weaponName)
	-- Simple detection of weapon type from name
	local isRifle = string.find(weaponName:lower(), "rifle") or 
		string.find(weaponName:lower(), "m4") or 
		string.find(weaponName:lower(), "ak") or
		string.find(weaponName:lower(), "g36")

	local isPistol = string.find(weaponName:lower(), "pistol") or
		string.find(weaponName:lower(), "glock") or
		string.find(weaponName:lower(), "m9")

	local isMelee = string.find(weaponName:lower(), "knife") or
		string.find(weaponName:lower(), "sword") or
		string.find(weaponName:lower(), "axe")

	local isSniper = string.find(weaponName:lower(), "sniper") or
		string.find(weaponName:lower(), "awp") or
		string.find(weaponName:lower(), "sr")

	local isShotgun = string.find(weaponName:lower(), "shotgun") or
		string.find(weaponName:lower(), "remington")

	-- Create basic configuration based on weapon type
	local config = {
		name = weaponName,
		displayName = weaponName,
		description = "Standard weapon",
		damage = 25,
		firerate = 600, -- RPM

		magazine = {
			size = 30,
			maxAmmo = 120,
			reloadTime = 2.5
		}
	}

	-- Customize based on weapon type
	if isRifle then
		config.type = "RIFLE"
		config.damage = 25
	elseif isPistol then
		config.type = "PISTOL"
		config.damage = 20
		config.magazine.size = 15
		config.magazine.maxAmmo = 60
	elseif isMelee then
		config.type = "MELEE"
		config.damage = 55
		config.backstabDamage = 100
		config.attackRate = 1.5
		config.attackRange = 3.0
		-- Melee weapons don't use magazines
		config.magazine = nil
	elseif isSniper then
		config.type = "SNIPER"
		config.damage = 100
		config.magazine.size = 5
		config.magazine.maxAmmo = 25
		config.firerate = 50
	elseif isShotgun then
		config.type = "SHOTGUN"
		config.damage = 15 -- Per pellet
		config.pelletCount = 8
		config.magazine.size = 8
		config.magazine.maxAmmo = 32
		config.firerate = 80
	end

	return config
end

-- Get a player's weapons
function WeaponManager:GetPlayerWeapons(player)
	return playerWeapons[player.UserId] or {}
end

-- Handle weapon equip
function WeaponManager:HandleWeaponEquip(player, weaponName, slot)
	-- Validate that player has this weapon
	local playerData = playerWeapons[player.UserId]
	if not playerData or not playerData[slot] or playerData[slot].name ~= weaponName then
		warn("Player " .. player.Name .. " tried to equip invalid weapon: " .. weaponName)
		return
	end

	-- Update player state
	playerStates[player.UserId].currentWeapon = weaponName
	playerStates[player.UserId].currentSlot = slot
	playerStates[player.UserId].state = "EQUIPPING"

	print("Player " .. player.Name .. " equipped " .. weaponName)
end

-- Handle weapon fired
function WeaponManager:HandleWeaponFired(player, weaponName, bulletData)
	-- Validate that player has this weapon equipped
	local playerState = playerStates[player.UserId]
	if not playerState or playerState.currentWeapon ~= weaponName then
		warn("Player " .. player.Name .. " tried to fire unequipped weapon: " .. weaponName)
		return
	end

	-- Get weapon data
	local slot = playerState.currentSlot
	local weaponInstance = playerWeapons[player.UserId][slot]

	-- Check if weapon has ammo
	if weaponInstance.config.type ~= "MELEE" and 
		weaponInstance.ammo.current <= 0 then
		print("Player " .. player.Name .. " tried to fire weapon with no ammo")
		return
	end

	-- Use ammo
	if weaponInstance.config.type ~= "MELEE" then
		weaponInstance.ammo.current = weaponInstance.ammo.current - 1
	end

	-- Update state
	playerState.state = "FIRING"

	-- Broadcast to other players (for bullet visualization, sound, etc.)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			remoteEvents.WeaponFired:FireClient(otherPlayer, player, weaponName, bulletData)
		end
	end

	print("Player " .. player.Name .. " fired " .. weaponName)
end

-- Handle hit registration
function WeaponManager:HandleHitRegistration(player, hitCharacter, hitData)
	-- Validate hit character exists
	if not hitCharacter or not hitCharacter:IsA("Model") or not hitCharacter:FindFirstChild("Humanoid") then
		warn("Invalid hit character from player " .. player.Name)
		return
	end

	-- Validate player has the weapon
	local playerState = playerStates[player.UserId]
	if not playerState or playerState.currentWeapon ~= hitData.weapon then
		warn("Player " .. player.Name .. " tried to register hit with unequipped weapon: " .. hitData.weapon)
		return
	end

	-- Calculate actual damage (server authority)
	local damage = hitData.damage

	-- Apply headshot multiplier
	if hitData.isHeadshot and hitData.hitPart == "Head" then
		damage = damage * 2 -- 2x damage for headshots
	end

	-- Apply backstab multiplier for melee
	if hitData.isBackstab then
		damage = damage * 2 -- 2x damage for backstabs
	end

	-- Get target humanoid
	local humanoid = hitCharacter:FindFirstChild("Humanoid")
	if humanoid and humanoid.Health > 0 then
		-- Apply damage
		humanoid:TakeDamage(damage)

		-- Broadcast hit to other players
		for _, otherPlayer in ipairs(Players:GetPlayers()) do
			if otherPlayer ~= player then
				remoteEvents.HitRegistration:FireClient(otherPlayer, player, hitCharacter, hitData)
			end
		end

		print("Player " .. player.Name .. " hit " .. hitCharacter.Name .. " for " .. damage .. " damage")
	end
end

-- Handle weapon reload
function WeaponManager:HandleWeaponReload(player, weaponName)
	-- Validate player has the weapon
	local playerState = playerStates[player.UserId]
	if not playerState or playerState.currentWeapon ~= weaponName then
		warn("Player " .. player.Name .. " tried to reload unequipped weapon: " .. weaponName)
		return
	end

	-- Get weapon data
	local slot = playerState.currentSlot
	local weaponInstance = playerWeapons[player.UserId][slot]

	-- Make sure it's a weapon that can be reloaded
	if weaponInstance.config.type == "MELEE" or not weaponInstance.ammo then
		return
	end

	-- Make sure reload is needed and possible
	if weaponInstance.ammo.current >= weaponInstance.ammo.maxSize or
		weaponInstance.ammo.reserve <= 0 then
		return
	end

	-- Update state
	playerState.state = "RELOADING"

	-- Calculate reload time
	local reloadTime
	if weaponInstance.ammo.current <= 0 and weaponInstance.config.magazine.reloadTimeEmpty then
		reloadTime = weaponInstance.config.magazine.reloadTimeEmpty
	else
		reloadTime = weaponInstance.config.magazine.reloadTime
	end

	-- After reload time, update ammo
	task.delay(reloadTime, function()
		-- Check if player still has the weapon equipped
		if playerState.currentWeapon ~= weaponName then
			return
		end

		-- Calculate ammo to add
		local neededAmmo = weaponInstance.ammo.maxSize - weaponInstance.ammo.current
		local availableAmmo = math.min(neededAmmo, weaponInstance.ammo.reserve)

		-- Update ammo counts
		weaponInstance.ammo.current = weaponInstance.ammo.current + availableAmmo
		weaponInstance.ammo.reserve = weaponInstance.ammo.reserve - availableAmmo

		-- Update state
		playerState.state = "IDLE"

		print("Player " .. player.Name .. " reloaded " .. weaponName ..
			" - Current: " .. weaponInstance.ammo.current .. 
			", Reserve: " .. weaponInstance.ammo.reserve)
	end)

	print("Player " .. player.Name .. " started reloading " .. weaponName)
end

-- Handle weapon state change
function WeaponManager:HandleWeaponState(player, state)
	-- Update player state
	local playerState = playerStates[player.UserId]
	if not playerState then
		return
	end

	playerState.state = state
end

-- Handle grenade events
function WeaponManager:HandleGrenadeEvent(player, action, data)
	if action == "ThrowGrenade" then
		-- Create server-side grenade physics object
		self:CreateGrenadePhysics(player, data)
	elseif action == "ExplodeInHand" then
		-- Handle explosion when cooked too long
		self:ExplodeGrenadeInHand(player)
	end
end

-- Create grenade physics
function WeaponManager:CreateGrenadePhysics(player, data)
	-- Get character
	local character = player.Character
	if not character then return end

	-- Create grenade part
	local grenade = Instance.new("Part")
	grenade.Name = "Grenade_" .. player.Name
	grenade.Shape = Enum.PartType.Ball
	grenade.Size = Vector3.new(0.8, 0.8, 0.8)
	grenade.Color = Color3.fromRGB(50, 100, 50)
	grenade.Material = Enum.Material.Metal
	grenade.Position = data.Position
	grenade.CanCollide = true
	grenade.CollisionGroup = "Grenades"

	-- Add custom physical properties
	grenade.CustomPhysicalProperties = PhysicalProperties.new(
		2, -- Density
		0.3, -- Friction
		0.3, -- Elasticity
		1, -- Friction weight
		1 -- Elasticity weight
	)

	-- Add velocity in throw direction
	grenade.Velocity = data.Direction * data.Force

	-- Add random spin
	grenade.RotVelocity = Vector3.new(
		math.random(-20, 20),
		math.random(-20, 20),
		math.random(-20, 20)
	)

	-- Add light
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 0, 0)
	light.Range = 3
	light.Brightness = 0.5
	light.Parent = grenade

	-- Parent to workspace
	grenade.Parent = workspace

	-- Schedule explosion after remaining time
	task.delay(data.RemainingTime, function()
		self:ExplodeGrenade(grenade)
	end)

	print("Player " .. player.Name .. " threw a grenade")
end

-- Explode a grenade
function WeaponManager:ExplodeGrenade(grenade)
	if not grenade or not grenade.Parent then return end

	local position = grenade.Position

	-- Create explosion
	local explosion = Instance.new("Explosion")
	explosion.Position = position
	explosion.BlastRadius = 15
	explosion.BlastPressure = 1000000 -- High pressure for physics effect
	explosion.DestroyJointRadiusPercent = 0
	explosion.Parent = workspace

	-- Handle explosion damage
	explosion.Hit:Connect(function(part, distance)
		-- Check if part belongs to a character
		local character = part:FindFirstAncestorOfClass("Model")
		if character and character:FindFirstChild("Humanoid") then
			local humanoid = character:FindFirstChild("Humanoid")

			-- Calculate damage based on distance
			local maxDamage = 100
			local minDamage = 10
			local maxDistance = explosion.BlastRadius

			local damage = maxDamage - ((distance / maxDistance) * (maxDamage - minDamage))
			damage = math.floor(damage)

			-- Apply damage
			if damage > 0 then
				humanoid:TakeDamage(damage)
			end
		end
	end)

	-- Remove grenade
	grenade:Destroy()

	print("Grenade exploded at " .. tostring(position))
end

-- Explode grenade in player's hand
function WeaponManager:ExplodeGrenadeInHand(player)
	-- Get character
	local character = player.Character
	if not character or not character:FindFirstChild("Humanoid") then return end

	-- Get humanoid
	local humanoid = character:FindFirstChild("Humanoid")

	-- Apply damage
	humanoid:TakeDamage(100) -- Death for cooking too long

	-- Create explosion effect at player's position
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		local explosion = Instance.new("Explosion")
		explosion.Position = rootPart.Position
		explosion.BlastRadius = 15
		explosion.BlastPressure = 1000000
		explosion.DestroyJointRadiusPercent = 0
		explosion.Parent = workspace
	end

	print("Player " .. player.Name .. " exploded grenade in hand")
end

-- Handle melee events
function WeaponManager:HandleMeleeEvent(player, action, data)
	-- Nothing special needed for melee - hits are handled through HitRegistration
	if action == "MeleeSwing" then
		print("Player " .. player.Name .. " swung melee weapon")
	end
end

-- Handle weapon data requests and updates
function WeaponManager:HandleWeaponData(player, action, data)
	if action == "LoadWeapon" then
		-- Player is loading a weapon
		local weaponName = data.weaponName
		local slot = data.slot

		-- Give weapon if player doesn't have it
		if not playerWeapons[player.UserId] or not playerWeapons[player.UserId][slot] then
			self:GiveWeapon(player, weaponName, slot)
		end
	elseif action == "GetAmmo" then
		-- Player is requesting ammo data
		local slot = data.slot

		if playerWeapons[player.UserId] and playerWeapons[player.UserId][slot] then
			-- Send ammo data back to client
			remoteEvents.WeaponData:FireClient(player, "AmmoData", {
				slot = slot,
				current = playerWeapons[player.UserId][slot].ammo.current,
				reserve = playerWeapons[player.UserId][slot].ammo.reserve,
				maxSize = playerWeapons[player.UserId][slot].ammo.maxSize
			})
		end
	elseif action == "GetAllWeapons" then
		-- Player is requesting all weapon data
		local weapons = {}

		-- Format weapon data
		for slot, weaponInstance in pairs(playerWeapons[player.UserId] or {}) do
			weapons[slot] = {
				name = weaponInstance.name,
				config = weaponInstance.config,
				ammo = weaponInstance.ammo,
				attachments = weaponInstance.attachments
			}
		end

		-- Send data back to client
		remoteEvents.WeaponData:FireClient(player, "AllWeaponsData", weapons)
	end
end

-- Calculate damage from a weapon
function WeaponManager:CalculateDamage(player, targetPlayer, weaponName, distance, hitPart, isHeadshot)
	-- Get weapon configuration
	local playerData = playerWeapons[player.UserId]
	local weaponInstance

	-- Find weapon instance
	for slot, weapon in pairs(playerData or {}) do
		if weapon.name == weaponName then
			weaponInstance = weapon
			break
		end
	end

	if not weaponInstance then
		return 0 -- Player doesn't have this weapon
	end

	-- Base damage
	local damage = weaponInstance.config.damage or 25

	-- Apply distance falloff
	if weaponInstance.config.damageRanges then
		local ranges = weaponInstance.config.damageRanges

		-- Sort ranges by distance
		table.sort(ranges, function(a, b)
			return a.distance < b.distance
		end)

		-- Find the appropriate range
		for i = 1, #ranges do
			if i == #ranges or (distance >= ranges[i].distance and distance < ranges[i+1].distance) then
				if i == #ranges then
					-- Beyond the last defined range
					damage = ranges[i].damage
				else
					-- Interpolate between ranges
					local rangeStart = ranges[i]
					local rangeEnd = ranges[i+1]
					local t = (distance - rangeStart.distance) / (rangeEnd.distance - rangeStart.distance)

					damage = rangeStart.damage + (rangeEnd.damage - rangeStart.damage) * t
				end
				break
			end
		end
	end

	-- Apply headshot multiplier
	if isHeadshot or hitPart == "Head" then
		damage = damage * 2 -- 2x damage for headshots
	end

	-- Apply team damage reduction if enabled
	if targetPlayer and targetPlayer.Team and player.Team == targetPlayer.Team then
		-- Check if friendly fire is enabled
		-- This is where you'd implement friendly fire rules
	end

	-- Round to nearest integer
	return math.floor(damage + 0.5)
end

-- Give all weapons to a player (admin/debug command)
function WeaponManager:GiveAllWeapons(player)
	-- Example weapons to give
	local weaponsList = {
		{"G36", "PRIMARY"},
		{"AK47", "PRIMARY"},
		{"M4A1", "PRIMARY"},
		{"AWP", "PRIMARY"},
		{"Shotgun", "PRIMARY"},
		{"Pistol", "SECONDARY"},
		{"Revolver", "SECONDARY"},
		{"Knife", "MELEE"},
		{"Grenade", "LETHAL"},
		{"Smoke", "TACTICAL"}
	}

	-- Give each weapon
	for _, weaponInfo in ipairs(weaponsList) do
		local weaponName, slot = unpack(weaponInfo)
		self:GiveWeapon(player, weaponName, slot)
	end

	print("Gave all weapons to player: " .. player.Name)
end

-- Set weapon ammo (admin/debug command)
function WeaponManager:SetWeaponAmmo(player, slot, current, reserve)
	if not playerWeapons[player.UserId] or not playerWeapons[player.UserId][slot] then
		warn("Player " .. player.Name .. " doesn't have a weapon in slot: " .. slot)
		return false
	end

	-- Update ammo
	local weaponInstance = playerWeapons[player.UserId][slot]
	if weaponInstance.ammo then
		weaponInstance.ammo.current = current or weaponInstance.ammo.maxSize
		weaponInstance.ammo.reserve = reserve or weaponInstance.ammo.maxSize * 5

		-- Notify client
		remoteEvents.WeaponData:FireClient(player, "AmmoData", {
			slot = slot,
			current = weaponInstance.ammo.current,
			reserve = weaponInstance.ammo.reserve,
			maxSize = weaponInstance.ammo.maxSize
		})

		print("Set ammo for player " .. player.Name .. "'s " .. weaponInstance.name .. 
			" to " .. weaponInstance.ammo.current .. "/" .. weaponInstance.ammo.reserve)
		return true
	end

	return false
end

-- Initialize the manager
WeaponManager:Initialize()

return WeaponManager