-- WeaponSystem.lua
-- Core weapon system that integrates with existing FPS systems
-- Place in ReplicatedStorage.FPSSystem.Modules

local WeaponSystem = {}
WeaponSystem.__index = WeaponSystem

-- Services
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local CollectionService = game:GetService("CollectionService")
local PhysicsService = game:GetService("PhysicsService")

-- Constants
local WEAPON_SLOTS = {
	PRIMARY = "PRIMARY",
	SECONDARY = "SECONDARY",
	MELEE = "MELEE",
	TACTICAL = "TACTICAL",
	LETHAL = "LETHAL"
}

local WEAPON_STATES = {
	IDLE = "IDLE",
	FIRING = "FIRING",
	RELOADING = "RELOADING",
	EQUIPPING = "EQUIPPING",
	UNEQUIPPING = "UNEQUIPPING",
	INSPECTING = "INSPECTING",
	SPRINTING = "SPRINTING",
	AIMING = "AIMING"
}

-- Constructor
function WeaponSystem.new(client)
	local self = setmetatable({}, WeaponSystem)

	-- Core references
	self.player = Players.LocalPlayer
	self.client = client
	self.camera = workspace.CurrentCamera

	-- Reference to other systems (will be injected)
	self.viewmodelSystem = nil
	self.firingSystem = nil
	self.attachmentSystem = nil
	self.crosshairSystem = nil
	self.effectsSystem = nil
	self.meleeSystem = nil
	self.cameraSystem = nil

	-- Weapon inventory
	self.weaponSlots = {}
	self.equippedSlot = nil
	self.equippedWeapon = nil
	self.lastEquippedSlot = nil
	self.weaponInstances = {}

	-- Weapon state
	self.currentState = WEAPON_STATES.IDLE
	self.isAiming = false
	self.isSprinting = false
	self.isReloading = false
	self.canFire = true
	self.canSwitch = true
	self.switchCooldown = 0.2 -- Time between weapon switches

	-- Animation states
	self.currentAnimationTrack = nil
	self.animationPriorities = {
		[WEAPON_STATES.FIRING] = 3,
		[WEAPON_STATES.RELOADING] = 4,
		[WEAPON_STATES.EQUIPPING] = 5,
		[WEAPON_STATES.UNEQUIPPING] = 5,
		[WEAPON_STATES.INSPECTING] = 2,
		[WEAPON_STATES.SPRINTING] = 1,
		[WEAPON_STATES.AIMING] = 1,
		[WEAPON_STATES.IDLE] = 0
	}

	-- Set up remote events for server communication
	self:setupRemoteEvents()

	-- Create RaycastHitboxes table for hit detection
	self.hitboxes = {}

	-- Register collision groups
	self:setupCollisionGroups()

	print("WeaponSystem initialized")
	return self
end

-- Set up remote events for server communication
function WeaponSystem:setupRemoteEvents()
	local eventsFolder = ReplicatedStorage:FindFirstChild("FPSSystem") and 
		ReplicatedStorage.FPSSystem:FindFirstChild("RemoteEvents")

	if not eventsFolder then
		eventsFolder = Instance.new("Folder")
		eventsFolder.Name = "RemoteEvents"

		local fpsSystem = ReplicatedStorage:FindFirstChild("FPSSystem")
		if not fpsSystem then
			fpsSystem = Instance.new("Folder")
			fpsSystem.Name = "FPSSystem"
			fpsSystem.Parent = ReplicatedStorage
		end

		eventsFolder.Parent = fpsSystem
	end

	-- Create weapon equip event
	self.weaponEquipEvent = eventsFolder:FindFirstChild("WeaponEquip")
	if not self.weaponEquipEvent then
		self.weaponEquipEvent = Instance.new("RemoteEvent")
		self.weaponEquipEvent.Name = "WeaponEquip"
		self.weaponEquipEvent.Parent = eventsFolder
	end

	-- Create weapon state event
	self.weaponStateEvent = eventsFolder:FindFirstChild("WeaponState")
	if not self.weaponStateEvent then
		self.weaponStateEvent = Instance.new("RemoteEvent")
		self.weaponStateEvent.Name = "WeaponState"
		self.weaponStateEvent.Parent = eventsFolder
	end

	-- Create weapon data event
	self.weaponDataEvent = eventsFolder:FindFirstChild("WeaponData")
	if not self.weaponDataEvent then
		self.weaponDataEvent = Instance.new("RemoteEvent")
		self.weaponDataEvent.Name = "WeaponData"
		self.weaponDataEvent.Parent = eventsFolder
	end

	print("Remote events set up")
end

-- Setup collision groups for weapon hitboxes
function WeaponSystem:setupCollisionGroups()
	-- Using new CollisionGroupAPI
	-- Try to create weapon collision groups
	pcall(function()
		-- Register weapon hitbox group if it doesn't exist
		PhysicsService:RegisterCollisionGroup("WeaponHitboxes")

		-- Set up weapon hitbox collision rules
		PhysicsService:CollisionGroupSetCollidable("WeaponHitboxes", "Default", false)
		PhysicsService:CollisionGroupSetCollidable("WeaponHitboxes", "Players", true)
		PhysicsService:CollisionGroupSetCollidable("WeaponHitboxes", "WeaponHitboxes", false)
	end)
end

-- Inject dependencies
function WeaponSystem:injectDependencies(dependencies)
	if dependencies.viewmodelSystem then
		self.viewmodelSystem = dependencies.viewmodelSystem
	end

	if dependencies.firingSystem then
		self.firingSystem = dependencies.firingSystem
	end

	if dependencies.attachmentSystem then
		self.attachmentSystem = dependencies.attachmentSystem
	end

	if dependencies.crosshairSystem then
		self.crosshairSystem = dependencies.crosshairSystem
	end

	if dependencies.effectsSystem then
		self.effectsSystem = dependencies.effectsSystem
	end

	if dependencies.meleeSystem then
		self.meleeSystem = dependencies.meleeSystem
	end

	if dependencies.cameraSystem then
		self.cameraSystem = dependencies.cameraSystem
	end

	print("Dependencies injected into WeaponSystem")
end

-- Load a weapon configuration and create weapon instance
function WeaponSystem:loadWeapon(weaponName, slot)
	if not weaponName or not slot then
		warn("Invalid weapon name or slot provided")
		return nil
	end

	-- Load weapon configuration
	local weaponConfig = self:getWeaponConfig(weaponName)
	if not weaponConfig then
		warn("Could not find configuration for weapon: " .. weaponName)
		return nil
	end

	-- Create weapon instance
	local weaponInstance = self:createWeaponInstance(weaponName, weaponConfig)
	if not weaponInstance then
		warn("Failed to create weapon instance: " .. weaponName)
		return nil
	end

	-- Store in weapon slots
	self.weaponSlots[slot] = weaponName
	self.weaponInstances[weaponName] = weaponInstance

	-- Notify server about weapon loading
	if self.weaponDataEvent then
		self.weaponDataEvent:FireServer("LoadWeapon", {
			weaponName = weaponName,
			slot = slot
		})
	end

	print("Loaded weapon: " .. weaponName .. " into slot: " .. slot)
	return weaponInstance
end

-- Create a weapon instance from configuration
function WeaponSystem:createWeaponInstance(weaponName, weaponConfig)
	local weaponModel = self:loadWeaponModel(weaponName)
	if not weaponModel then
		warn("Failed to load weapon model: " .. weaponName)
		return nil
	end

	-- Create weapon instance
	local weaponInstance = {
		name = weaponName,
		config = weaponConfig,
		model = weaponModel,
		viewmodel = nil, -- Will be created when equipped

		-- State tracking
		ammo = {
			current = weaponConfig.magazine.size,
			reserve = weaponConfig.magazine.maxAmmo,
			maxSize = weaponConfig.magazine.size
		},

		-- Attachments
		attachments = {},

		-- Animation tracks
		animations = {},

		-- Hitboxes
		hitboxes = {},

		-- Time tracking
		lastFireTime = 0,
		equippedTime = 0
	}

	-- Check if firing system supports this weapon type
	if self.firingSystem and weaponConfig.type ~= "MELEE" then
		weaponInstance.canUseFireSystem = true
	end

	-- Check if melee system should be used
	if self.meleeSystem and weaponConfig.type == "MELEE" then
		weaponInstance.canUseMeleeSystem = true
	end

	-- Setup hitboxes (if applicable)
	if weaponConfig.hitboxData then
		self:setupWeaponHitboxes(weaponInstance, weaponConfig.hitboxData)
	end

	return weaponInstance
end

-- Load weapon model from ReplicatedStorage
function WeaponSystem:loadWeaponModel(weaponName)
	-- Check FPSSystem folder structure first
	local fpsSystem = ReplicatedStorage:FindFirstChild("FPSSystem")
	local weaponsFolder = fpsSystem and fpsSystem:FindFirstChild("WeaponModels")

	if weaponsFolder then
		local weaponFolder = weaponsFolder:FindFirstChild(weaponName)
		if weaponFolder and weaponFolder:FindFirstChild("WorldModel") then
			return weaponFolder.WorldModel:Clone()
		end
	end

	-- Try other common locations
	local potentialPaths = {
		ReplicatedStorage.Weapons,
		ReplicatedStorage.WeaponModels,
		ReplicatedStorage.Assets and ReplicatedStorage.Assets.Weapons,
		ReplicatedStorage.Models and ReplicatedStorage.Models.Weapons
	}

	for _, path in ipairs(potentialPaths) do
		if path and path:FindFirstChild(weaponName) then
			local model = path[weaponName]
			if model:IsA("Model") then
				return model:Clone()
			end
		end
	end

	-- Create placeholder model if nothing found
	print("Creating placeholder model for weapon: " .. weaponName)
	return self:createPlaceholderModel(weaponName)
end

-- Create a placeholder weapon model
function WeaponSystem:createPlaceholderModel(weaponName)
	local model = Instance.new("Model")
	model.Name = weaponName

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.5, 0.2, 2)
	handle.Color = Color3.fromRGB(80, 80, 80)
	handle.Material = Enum.Material.Metal
	handle.Anchored = true
	handle.CanCollide = false
	handle.Parent = model
	model.PrimaryPart = handle

	-- Create barrel part
	local barrel = Instance.new("Part")
	barrel.Name = "Barrel"
	barrel.Size = Vector3.new(0.2, 0.2, 1)
	barrel.Color = Color3.fromRGB(60, 60, 60)
	barrel.Material = Enum.Material.Metal
	barrel.Anchored = true
	barrel.CanCollide = false
	barrel.CFrame = handle.CFrame * CFrame.new(0, 0, -1.5)
	barrel.Parent = model

	-- Create magazine part
	local magazine = Instance.new("Part")
	magazine.Name = "Magazine"
	magazine.Size = Vector3.new(0.3, 0.8, 0.2)
	magazine.Color = Color3.fromRGB(40, 40, 40)
	magazine.Material = Enum.Material.Metal
	magazine.Anchored = true
	magazine.CanCollide = false
	magazine.CFrame = handle.CFrame * CFrame.new(0, -0.5, 0)
	magazine.Parent = model

	-- Create muzzle attachment
	local muzzleAttach = Instance.new("Attachment")
	muzzleAttach.Name = "MuzzlePoint"
	muzzleAttach.Position = Vector3.new(0, 0, -0.5)
	muzzleAttach.Parent = barrel

	-- Create shell ejection attachment
	local shellAttach = Instance.new("Attachment")
	shellAttach.Name = "ShellEjectPoint"
	shellAttach.Position = Vector3.new(0.3, 0, 0)
	shellAttach.Parent = handle

	-- Create aim point attachment
	local aimAttach = Instance.new("Attachment")
	aimAttach.Name = "AimPoint"
	aimAttach.Position = Vector3.new(0, 0.2, 0)
	aimAttach.Parent = handle

	return model
end

-- Get weapon configuration from WeaponConfig module
function WeaponSystem:getWeaponConfig(weaponName)
	-- Try to require WeaponConfig module
	local success, WeaponConfig = pcall(function()
		return require(ReplicatedStorage.FPSSystem.Modules.WeaponConfig)
	end)

	if success and WeaponConfig and WeaponConfig.Weapons and WeaponConfig.Weapons[weaponName] then
		return WeaponConfig.Weapons[weaponName]
	end

	-- If failed, return a default config
	print("Using default configuration for weapon: " .. weaponName)
	return self:getDefaultWeaponConfig(weaponName)
end

-- Create default weapon configuration
function WeaponSystem:getDefaultWeaponConfig(weaponName)
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

	-- Create configuration based on weapon type
	if isRifle then
		return {
			name = weaponName,
			displayName = weaponName,
			description = "Standard assault rifle",
			type = "RIFLE",

			-- Base stats
			damage = 25,
			firerate = 600, -- RPM
			velocity = 1000, -- Studs/sec

			-- Damage falloff
			damageRanges = {
				{distance = 0, damage = 25},
				{distance = 50, damage = 22},
				{distance = 100, damage = 18},
				{distance = 150, damage = 15}
			},

			-- Recoil properties
			recoil = {
				vertical = 1.2,
				horizontal = 0.3,
				recovery = 0.95,
				pattern = "rising"
			},

			-- Spread/Accuracy
			spread = {
				base = 1.0,
				moving = 1.5,
				jumping = 2.5,
				sustained = 0.1,
				maxSustained = 2.0,
				recovery = 0.95
			},

			-- Mobility
			mobility = {
				adsSpeed = 0.3,
				walkSpeed = 14,
				sprintSpeed = 20,
				equipTime = 0.4
			},

			-- Magazine settings
			magazine = {
				size = 30,
				maxAmmo = 120,
				reloadTime = 2.5,
				reloadTimeEmpty = 3.0
			},

			-- Advanced settings
			penetration = 1.5,
			bulletDrop = 0.1,
			firingMode = "FULL_AUTO",

			-- Effects
			muzzleFlash = {
				size = 1.0,
				brightness = 1.0,
				color = Color3.fromRGB(255, 200, 100)
			},

			tracers = {
				enabled = true,
				color = Color3.fromRGB(255, 180, 100),
				width = 0.05,
				frequency = 3
			},

			-- Sounds
			sounds = {
				fire = "rbxassetid://6805664253",
				reload = "rbxassetid://6805664397",
				reloadEmpty = "rbxassetid://6842081192",
				equip = "rbxassetid://6805664253",
				empty = "rbxassetid://3744371342"
			},

			-- Animation IDs
			animations = {
				idle = "rbxassetid://9949926480",
				fire = "rbxassetid://9949926480",
				reload = "rbxassetid://9949926480",
				reloadEmpty = "rbxassetid://9949926480",
				equip = "rbxassetid://9949926480",
				sprint = "rbxassetid://9949926480"
			}
		}
	elseif isPistol then
		return {
			name = weaponName,
			displayName = weaponName,
			description = "Standard sidearm",
			type = "PISTOL",

			-- Base stats
			damage = 20,
			firerate = 450,
			velocity = 800,

			-- Other properties similar to rifle but adjusted...
			magazine = {
				size = 15,
				maxAmmo = 60,
				reloadTime = 1.8,
				reloadTimeEmpty = 2.2
			},

			firingMode = "SEMI_AUTO"

			-- Other properties would go here, abbreviated for clarity
		}
	elseif isMelee then
		return {
			name = weaponName,
			displayName = weaponName,
			description = "Melee weapon",
			type = "MELEE",

			-- Melee-specific stats
			damage = 55,
			backstabDamage = 100,
			attackRate = 1.5,
			attackRange = 3.0,
			attackType = "slash",

			-- Mobility
			mobility = {
				walkSpeed = 16,
				sprintSpeed = 22,
				equipTime = 0.2
			},

			-- Sounds
			sounds = {
				swing = "rbxassetid://5810753638",
				hit = "rbxassetid://3744370687",
				hitCritical = "rbxassetid://3744371342",
				equip = "rbxassetid://6842081192"
			},

			-- Animations
			animations = {
				idle = "rbxassetid://9949926480",
				attack = "rbxassetid://9949926480",
				attackAlt = "rbxassetid://9949926480",
				equip = "rbxassetid://9949926480",
				sprint = "rbxassetid://9949926480"
			}
		}
	elseif isSniper then
		return {
			name = weaponName,
			displayName = weaponName,
			description = "Long-range precision rifle",
			type = "SNIPER",

			-- Sniper-specific stats
			damage = 100,
			firerate = 50,
			velocity = 2000,

			-- Other sniper properties
			firingMode = "BOLT_ACTION",

			-- Scope settings
			scope = {
				defaultZoom = 8.0,
				maxZoom = 10.0,
				scopeType = "GUI"
			},

			magazine = {
				size = 5,
				maxAmmo = 25,
				reloadTime = 3.5,
				reloadTimeEmpty = 3.5
			}

			-- Other properties would go here, abbreviated for clarity
		}
	elseif isShotgun then
		return {
			name = weaponName,
			displayName = weaponName,
			description = "Close-range shotgun",
			type = "SHOTGUN",

			-- Shotgun-specific stats
			damage = 15, -- Per pellet
			firerate = 80,
			velocity = 800,

			-- Shotgun pellet properties
			pelletCount = 8,
			pelletSpread = 4.0,

			firingMode = "PUMP_ACTION",

			magazine = {
				size = 8,
				maxAmmo = 32,
				reloadTime = 0.6, -- Per shell
				reloadType = "incremental"
			}

			-- Other properties would go here, abbreviated for clarity
		}
	else
		-- Default generic weapon
		return {
			name = weaponName,
			displayName = weaponName,
			description = "Standard weapon",
			type = "RIFLE",

			-- Base stats
			damage = 25,
			firerate = 600,
			velocity = 1000,

			-- Magazine
			magazine = {
				size = 30,
				maxAmmo = 120,
				reloadTime = 2.5,
				reloadTimeEmpty = 3.0
			},

			-- Firing mode
			firingMode = "FULL_AUTO"

			-- Other properties would go here, abbreviated for clarity
		}
	end
end

-- Setup weapon hitboxes using new RaycastHitbox system
function WeaponSystem:setupWeaponHitboxes(weaponInstance, hitboxData)
	-- Only use for melee weapons
	if weaponInstance.config.type ~= "MELEE" then return end

	-- First, check if we can require the latest RaycastHitbox module
	local success, RaycastHitboxModule = pcall(function()
		return require(ReplicatedStorage:WaitForChild("RaycastHitboxV4", 1))
	end)

	if not success then
		warn("Failed to require RaycastHitbox module. Hitboxes won't be created.")
		return
	end

	local RaycastHitbox = RaycastHitboxModule.new(weaponInstance.model)

	-- Create hitboxes based on hitboxData
	for partName, data in pairs(hitboxData) do
		local part = weaponInstance.model:FindFirstChild(partName)
		if part and part:IsA("BasePart") then
			-- Add part to hitbox
			RaycastHitbox:AddHitbox(part)
		end
	end

	-- Set hitbox parameters
	RaycastHitbox.DetectionMode = RaycastHitboxModule.DetectionMode.Precise
	RaycastHitbox.Visualizer = true -- Enable in dev mode, disable in production

	-- Set collision group
	RaycastHitbox.RaycastParams.CollisionGroup = "WeaponHitboxes"

	-- Store hitbox in weapon instance
	weaponInstance.hitboxes.raycastHitbox = RaycastHitbox

	-- Setup hit detection
	RaycastHitbox.OnHit:Connect(function(hit, humanoid)
		if humanoid then
			local character = humanoid.Parent
			if character then
				-- Check if hit was a backstab (for melee weapons)
				local isBackstab = self:checkBackstab(character, weaponInstance)

				-- Calculate damage
				local damage = isBackstab and weaponInstance.config.backstabDamage or weaponInstance.config.damage

				-- Register hit with server
				self:registerHit(character, humanoid, damage, isBackstab, hit.Name)

				-- Show hit effect
				if self.effectsSystem then
					self.effectsSystem:createHitEffect(hit.Position, isBackstab)
				end

				-- Play hit sound
				self:playHitSound(weaponInstance, isBackstab)

				-- Show hitmarker
				if self.crosshairSystem then
					local isHeadshot = hit.Name == "Head"
					self.crosshairSystem:hitmarker(isHeadshot or isBackstab)
				end
			end
		end
	end)
end

-- Check if an attack is a backstab (for melee weapons)
function WeaponSystem:checkBackstab(character, weaponInstance)
	-- Get character looking direction
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end

	-- Get attack direction (from player to target)
	local attackDirection = (rootPart.Position - self.camera.CFrame.Position).Unit

	-- Get character look direction
	local characterLookVector = rootPart.CFrame.LookVector

	-- Check if attack is coming from behind (dot product < 0)
	return attackDirection:Dot(characterLookVector) > 0.5
end

-- Register hit with server
function WeaponSystem:registerHit(character, humanoid, damage, isBackstab, hitPartName)
	local hitEvent = ReplicatedStorage:FindFirstChild("FPSSystem") and 
		ReplicatedStorage.FPSSystem:FindFirstChild("RemoteEvents") and
		ReplicatedStorage.FPSSystem.RemoteEvents:FindFirstChild("HitRegistration")

	if hitEvent then
		-- Create hit data
		local hitData = {
			weapon = self.equippedWeapon and self.equippedWeapon.name or "Unknown",
			damage = damage,
			isBackstab = isBackstab,
			hitPart = hitPartName,
			isHeadshot = hitPartName == "Head"
		}

		-- Send hit data to server
		hitEvent:FireServer(character, hitData)
	end
end

-- Play hit sound for melee weapons
function WeaponSystem:playHitSound(weaponInstance, isBackstab)
	if not weaponInstance.config.sounds then return end

	local soundId = isBackstab and 
		weaponInstance.config.sounds.hitCritical or 
		weaponInstance.config.sounds.hit

	if not soundId then return end

	-- Create sound
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = 0.5
	sound.Parent = self.player.PlayerGui
	sound:Play()

	-- Auto cleanup
	game:GetService("Debris"):AddItem(sound, 2)
end

-- Equip a weapon from a slot
function WeaponSystem:equipWeapon(slot)
	if not slot or not self.weaponSlots[slot] then
		warn("Invalid slot or no weapon in slot: " .. tostring(slot))
		return false
	end

	-- Check if we can switch weapons
	if not self.canSwitch then
		return false
	end

	-- Get weapon from slot
	local weaponName = self.weaponSlots[slot]
	local weaponInstance = self.weaponInstances[weaponName]

	if not weaponInstance then
		warn("No weapon instance found for: " .. weaponName)
		return false
	end

	-- Store last equipped slot
	self.lastEquippedSlot = self.equippedSlot

	-- Remember current weapon for unequipping
	local previousWeapon = self.equippedWeapon

	-- Set cooldown
	self.canSwitch = false

	-- Start unequipping current weapon (if any)
	if previousWeapon then
		self:setState(WEAPON_STATES.UNEQUIPPING)
		self:playAnimation(previousWeapon, "unequip", function()
			-- Clear old weapon
			self:clearEquippedWeapon()

			-- Complete the equip with new weapon
			self:finishEquipWeapon(slot, weaponName, weaponInstance)
		end)
	else
		-- No previous weapon, equip directly
		self:finishEquipWeapon(slot, weaponName, weaponInstance)
	end

	return true
end

-- Finish equipping a weapon after unequipping the previous one
function WeaponSystem:finishEquipWeapon(slot, weaponName, weaponInstance)
	-- Update state
	self.equippedSlot = slot
	self.equippedWeapon = weaponInstance
	weaponInstance.equippedTime = tick()

	-- Reset weapon state
	self:setState(WEAPON_STATES.EQUIPPING)
	self.isAiming = false
	self.isSprinting = false
	self.isReloading = false

	-- Equip in viewmodel system
	if self.viewmodelSystem then
		-- Check if we need to create a viewmodel first
		if not weaponInstance.viewmodel then
			-- Clone world model for viewmodel
			weaponInstance.viewmodel = weaponInstance.model:Clone()
			weaponInstance.viewmodel.Name = weaponName .. "Viewmodel"
		end

		-- Equip in viewmodel system
		self.viewmodelSystem:equipWeapon(weaponInstance.viewmodel, weaponInstance.config.type)
	end

	-- Set up firing system
	if self.firingSystem and weaponInstance.canUseFireSystem then
		self.firingSystem:setWeapon(weaponInstance.viewmodel, weaponInstance.config)
	end

	-- Set up melee system
	if self.meleeSystem and weaponInstance.canUseMeleeSystem then
		if weaponInstance.hitboxes.raycastHitbox then
			-- Enable hitbox when equipped
			weaponInstance.hitboxes.raycastHitbox:HitStart()
		end
	end

	-- Update crosshair
	if self.crosshairSystem then
		self.crosshairSystem:updateFromWeaponState(weaponInstance.config, false)
	end

	-- Play equip animation
	self:playAnimation(weaponInstance, "equip", function()
		-- Set to idle state once equipped
		self:setState(WEAPON_STATES.IDLE)

		-- Allow weapon switching again
		task.delay(self.switchCooldown, function()
			self.canSwitch = true
		end)
	end)

	-- Notify server about weapon equip
	if self.weaponEquipEvent then
		self.weaponEquipEvent:FireServer(weaponName, slot)
	end

	print("Equipped weapon: " .. weaponName)
end

-- Clear the currently equipped weapon
function WeaponSystem:clearEquippedWeapon()
	if not self.equippedWeapon then return end

	-- Stop hitboxes if it's a melee weapon
	if self.equippedWeapon.hitboxes.raycastHitbox then
		self.equippedWeapon.hitboxes.raycastHitbox:HitStop()
	end

	-- Reset state
	self.equippedWeapon = nil
	self.equippedSlot = nil
end

-- Set weapon state
function WeaponSystem:setState(state)
	if self.currentState == state then return end

	local previousState = self.currentState
	self.currentState = state

	-- Notify server about state change
	if self.weaponStateEvent then
		self.weaponStateEvent:FireServer(state)
	end

	-- Handle state-specific actions
	if state == WEAPON_STATES.AIMING then
		-- Update viewmodel
		if self.viewmodelSystem then
			self.viewmodelSystem:setAiming(true)
		end

		-- Update camera FOV
		if self.cameraSystem then
			local weaponConfig = self.equippedWeapon and self.equippedWeapon.config
			local zoomLevel = weaponConfig and weaponConfig.scope and weaponConfig.scope.defaultZoom
			self.cameraSystem:setAiming(true, zoomLevel)
		end

		-- Update crosshair
		if self.crosshairSystem and self.equippedWeapon then
			self.crosshairSystem:updateFromWeaponState(self.equippedWeapon.config, true)
		end
	elseif state == WEAPON_STATES.SPRINTING then
		-- Update viewmodel
		if self.viewmodelSystem then
			self.viewmodelSystem:setSprinting(true)
		end

		-- Update movement
		if self.cameraSystem then
			self.cameraSystem:setSprinting(true)
		end

		-- Cancel aiming if aiming
		if self.isAiming then
			self.isAiming = false

			-- Update viewmodel aiming state
			if self.viewmodelSystem then
				self.viewmodelSystem:setAiming(false)
			end

			-- Update camera
			if self.cameraSystem then
				self.cameraSystem:setAiming(false)
			end

			-- Update crosshair
			if self.crosshairSystem and self.equippedWeapon then
				self.crosshairSystem:updateFromWeaponState(self.equippedWeapon.config, false)
			end
		end
	elseif state == WEAPON_STATES.RELOADING then
		-- Cancel aiming if aiming
		if self.isAiming then
			self.isAiming = false

			-- Update viewmodel aiming state
			if self.viewmodelSystem then
				self.viewmodelSystem:setAiming(false)
			end

			-- Update camera
			if self.cameraSystem then
				self.cameraSystem:setAiming(false)
			end
		end
	elseif state == WEAPON_STATES.IDLE then
		-- Reset to normal state if coming from another state
		if previousState == WEAPON_STATES.AIMING then
			-- Update viewmodel
			if self.viewmodelSystem then
				self.viewmodelSystem:setAiming(false)
			end

			-- Update camera
			if self.cameraSystem then
				self.cameraSystem:setAiming(false)
			end

			-- Update crosshair
			if self.crosshairSystem and self.equippedWeapon then
				self.crosshairSystem:updateFromWeaponState(self.equippedWeapon.config, false)
			end
		elseif previousState == WEAPON_STATES.SPRINTING then
			-- Update viewmodel
			if self.viewmodelSystem then
				self.viewmodelSystem:setSprinting(false)
			end

			-- Update movement
			if self.cameraSystem then
				self.cameraSystem:setSprinting(false)
			end
		end
	end
end

-- Handle aim input
function WeaponSystem:handleAiming(isAiming)
	-- Update aiming state
	self.isAiming = isAiming

	-- Update weapon state
	if isAiming then
		self:setState(WEAPON_STATES.AIMING)
	else
		-- Return to previous state
		if self.isSprinting then
			self:setState(WEAPON_STATES.SPRINTING)
		else
			self:setState(WEAPON_STATES.IDLE)
		end
	end

	return true
end

-- Handle sprint input
function WeaponSystem:handleSprinting(isSprinting)
	-- Update sprinting state
	self.isSprinting = isSprinting

	-- Update weapon state
	if isSprinting and not self.isAiming then
		self:setState(WEAPON_STATES.SPRINTING)
	else if not isSprinting then
			-- Return to previous state
			if self.isAiming then
				self:setState(WEAPON_STATES.AIMING)
			else
				self:setState(WEAPON_STATES.IDLE)
			end
		end

		return true
	end

	-- Handle reload input
	function WeaponSystem:handleReload()
		-- Check if we can reload
		if not self.equippedWeapon or 
			self.isReloading or 
			self.currentState == WEAPON_STATES.EQUIPPING or
			self.currentState == WEAPON_STATES.UNEQUIPPING then
			return false
		end

		-- Get ammo data
		local ammo = self.equippedWeapon.ammo

		-- Check if we need to reload
		if ammo.current >= ammo.maxSize or ammo.reserve <= 0 then
			return false
		end

		-- Set reload state
		self.isReloading = true
		self:setState(WEAPON_STATES.RELOADING)

		-- Get reload time
		local reloadTime
		if ammo.current <= 0 and self.equippedWeapon.config.magazine.reloadTimeEmpty then
			reloadTime = self.equippedWeapon.config.magazine.reloadTimeEmpty
		else
			reloadTime = self.equippedWeapon.config.magazine.reloadTime
		end

		-- Play reload animation
		local animName = ammo.current <= 0 ? "reloadEmpty" : "reload"
		self:playAnimation(self.equippedWeapon, animName, function()
			-- Calculate ammo to add
			local neededAmmo = ammo.maxSize - ammo.current
			local availableAmmo = math.min(neededAmmo, ammo.reserve)

			-- Update ammo counts
			ammo.current = ammo.current + availableAmmo
			ammo.reserve = ammo.reserve - availableAmmo

			-- Reset reload state
			self.isReloading = false

			-- Return to previous state
			if self.isAiming then
				self:setState(WEAPON_STATES.AIMING)
			else if self.isSprinting then
					self:setState(WEAPON_STATES.SPRINTING)
				else
					self:setState(WEAPON_STATES.IDLE)
				end

				print("Reload complete - Current: " .. ammo.current .. ", Reserve: " .. ammo.reserve)
			end)

		return true
	end

	-- Handle firing input
	function WeaponSystem:handleFiring(isPressed)
		-- Check if we have a weapon equipped
		if not self.equippedWeapon then
			return false
		end

		-- Check if we can fire
		if self.isReloading or 
			self.currentState == WEAPON_STATES.EQUIPPING or
			self.currentState == WEAPON_STATES.UNEQUIPPING or
			(self.isSprinting and not self.isAiming) then
			return false
		end

		-- Delegate firing based on weapon type
		if self.equippedWeapon.canUseFireSystem and self.firingSystem then
			-- Handle using firing system
			return self.firingSystem:handleFiring(isPressed)
		elseif self.equippedWeapon.canUseMeleeSystem and self.meleeSystem then
			-- Handle using melee system
			return self.meleeSystem:handleMouseButton1(isPressed)
		end

		return false
	end

	-- Play a weapon animation
	function WeaponSystem:playAnimation(weaponInstance, animationName, callback)
		if not weaponInstance or not weaponInstance.config.animations then
			if callback then callback() end
			return nil
		end

		-- Check if animation exists
		local animId = weaponInstance.config.animations[animationName]
		if not animId then
			if callback then callback() end
			return nil
		end

		-- Get or create animation track
		local animTrack = weaponInstance.animations[animationName]
		if not animTrack then
			-- Try to load animation
			local success, animation = pcall(function()
				local animator = self.viewmodelSystem and 
					self.viewmodelSystem.viewmodelRig and 
					self.viewmodelSystem.viewmodelRig:FindFirstChildOfClass("Animator")

				if not animator then 
					-- Try to create animator
					animator = Instance.new("Animator")
					animator.Parent = self.viewmodelSystem.viewmodelRig
				end

				-- Create animation from ID
				local anim = Instance.new("Animation")
				anim.AnimationId = animId
				return animator:LoadAnimation(anim)
			end)

			if not success or not animation then
				warn("Failed to load animation: " .. animationName)
				if callback then callback() end
				return nil
			end

			weaponInstance.animations[animationName] = animation
			animTrack = animation
		end

		-- Set up callback when animation finishes
		if callback then
			local connection
			connection = animTrack.Stopped:Connect(function()
				connection:Disconnect()
				callback()
			end)
		end

		-- Play the animation
		animTrack:Play()

		return animTrack
	end

	-- Handle quick switch back to last weapon
	function WeaponSystem:quickSwitch()
		if self.lastEquippedSlot then
			return self:equipWeapon(self.lastEquippedSlot)
		end
		return false
	end

	-- Update function (called every frame)
	function WeaponSystem:update(dt)
		-- Update equipped weapon
		if self.equippedWeapon then
			-- Update hitboxes for melee weapons
			if self.equippedWeapon.hitboxes.raycastHitbox then
				self.equippedWeapon.hitboxes.raycastHitbox:HighlightHitboxes()
			end
		end
	end

	-- Get current ammo state
	function WeaponSystem:getCurrentAmmo()
		if not self.equippedWeapon then
			return {current = 0, reserve = 0, maxSize = 0}
		end

		return {
			current = self.equippedWeapon.ammo.current,
			reserve = self.equippedWeapon.ammo.reserve,
			maxSize = self.equippedWeapon.ammo.maxSize
		}
	end

	-- Get current weapon state
	function WeaponSystem:getCurrentState()
		return {
			state = self.currentState,
			isAiming = self.isAiming,
			isSprinting = self.isSprinting,
			isReloading = self.isReloading,
			equippedSlot = self.equippedSlot,
			equippedWeapon = self.equippedWeapon and self.equippedWeapon.name or nil
		}
	end

	-- Clean up
	function WeaponSystem:cleanup()
		-- Stop all hitboxes
		for _, weaponInstance in pairs(self.weaponInstances) do
			if weaponInstance.hitboxes.raycastHitbox then
				weaponInstance.hitboxes.raycastHitbox:Destroy()
			end
		end

		print("WeaponSystem cleaned up")
	end

	return WeaponSystem