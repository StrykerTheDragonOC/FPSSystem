-- FiringSystem.lua
-- Advanced weapon firing system with realistic bullet physics
-- Place in ReplicatedStorage.FPSSystem.Modules

local FiringSystem = {}
FiringSystem.__index = FiringSystem

-- Services
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

-- Constants
local FIRING_SETTINGS = {
	-- Bullet physics
	DEFAULT_VELOCITY = 1000,   -- Default bullet velocity (studs/sec)
	GRAVITY = Vector3.new(0, -workspace.Gravity, 0), -- Physics gravity
	DRAG_COEFFICIENT = 0.1,    -- Air resistance factor

	-- Materials penetration multipliers
	MATERIAL_PENETRATION = {
		[Enum.Material.Plastic] = 1.0,
		[Enum.Material.Wood] = 1.5, 
		[Enum.Material.Slate] = 0.8,
		[Enum.Material.Concrete] = 0.7,
		[Enum.Material.CorrodedMetal] = 1.2,
		[Enum.Material.DiamondPlate] = 0.9,
		[Enum.Material.Foil] = 2.0,
		[Enum.Material.Grass] = 2.0,
		[Enum.Material.Ice] = 1.5,
		[Enum.Material.Marble] = 0.6,
		[Enum.Material.Metal] = 0.8,
		[Enum.Material.Neon] = 1.0,
		[Enum.Material.SmoothPlastic] = 1.0,
		[Enum.Material.Glass] = 1.8,
		-- Add more materials as needed
	},

	-- Damage falloff
	DEFAULT_DAMAGE_RANGES = {
		{distance = 0, multiplier = 1.0},    -- Full damage at point blank
		{distance = 50, multiplier = 0.9},    -- 90% damage at 50 studs
		{distance = 100, multiplier = 0.75},  -- 75% damage at 100 studs
		{distance = 200, multiplier = 0.5},   -- 50% damage at 200 studs
	},

	-- Visual effects
	BULLET_TRAIL_WIDTH = 0.05,
	BULLET_TRAIL_LIFETIME = 0.1,
	MUZZLE_FLASH_DURATION = 0.05,
	SHELL_CASING_LIFETIME = 2.0,

	-- Hitmarker settings
	HITMARKER_DURATION = 0.1,
	HITMARKER_SIZE = 20,
	HITMARKER_COLOR = Color3.fromRGB(255, 255, 255),
	HITMARKER_HEADSHOT_COLOR = Color3.fromRGB(255, 0, 0),

	-- Ammo and reloading
	DEFAULT_MAGAZINE_SIZE = 30,
	DEFAULT_RESERVE_AMMO = 120,
	DEFAULT_RELOAD_TIME = 2.5,

	-- FireModes
	FIRE_MODES = {
		FULL_AUTO = "FULL_AUTO",
		SEMI_AUTO = "SEMI_AUTO",
		BURST = "BURST",
		BOLT_ACTION = "BOLT_ACTION",
		PUMP_ACTION = "PUMP_ACTION"
	},

	-- Raycasting
	MAX_BOUNCES = 3,
	MAX_PENETRATIONS = 3,
	RAYCAST_RESOLUTION = 10  -- Higher = more accurate but more expensive
}

-- Create a new FiringSystem
function FiringSystem.new(viewmodelSystem)
	local self = setmetatable({}, FiringSystem)

	-- Core references
	self.player = Players.LocalPlayer
	self.camera = workspace.CurrentCamera
	self.viewmodel = viewmodelSystem

	-- Firing state
	self.currentWeapon = nil
	self.weaponConfig = nil
	self.isFiring = false
	self.canFire = true
	self.isReloading = false
	self.lastFireTime = 0
	self.burstCount = 0

	-- Ammo tracking
	self.ammoData = {}

	-- Create effects container
	self.effectsFolder = Instance.new("Folder")
	self.effectsFolder.Name = "FiringEffects"
	self.effectsFolder.Parent = workspace

	-- Set up remote events
	self:setupRemoteEvents()

	-- Create crosshair if enabled
	self:createCrosshair()

	-- Register collision groups
	self:setupCollisionGroups()

	print("FiringSystem initialized")
	return self
end

-- Set up remote events for server communication
function FiringSystem:setupRemoteEvents()
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

	-- Create weapon fired event
	self.weaponFiredEvent = eventsFolder:FindFirstChild("WeaponFired")
	if not self.weaponFiredEvent then
		self.weaponFiredEvent = Instance.new("RemoteEvent")
		self.weaponFiredEvent.Name = "WeaponFired"
		self.weaponFiredEvent.Parent = eventsFolder
	end

	-- Create hit registration event
	self.hitRegEvent = eventsFolder:FindFirstChild("HitRegistration")
	if not self.hitRegEvent then
		self.hitRegEvent = Instance.new("RemoteEvent")
		self.hitRegEvent.Name = "HitRegistration"
		self.hitRegEvent.Parent = eventsFolder
	end

	-- Create weapon reload event
	self.reloadEvent = eventsFolder:FindFirstChild("WeaponReload")
	if not self.reloadEvent then
		self.reloadEvent = Instance.new("RemoteEvent")
		self.reloadEvent.Name = "WeaponReload"
		self.reloadEvent.Parent = eventsFolder
	end

	print("Remote events set up")
end

-- Register collision groups for bullets
function FiringSystem:setupCollisionGroups()
	-- Try to create bullet collision group
	pcall(function()
		-- Register bullet group if it doesn't exist
		PhysicsService:RegisterCollisionGroup("Bullets")

		-- Set up bullet collision rules
		PhysicsService:CollisionGroupSetCollidable("Bullets", "Default", true)
		PhysicsService:CollisionGroupSetCollidable("Bullets", "Players", true)

		-- Make bullets not collide with other bullets
		PhysicsService:CollisionGroupSetCollidable("Bullets", "Bullets", false)
	end)
end

-- Create crosshair GUI
function FiringSystem:createCrosshair()
	-- This is just a basic implementation
	-- For a more comprehensive crosshair system, use CrosshairSystem

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "BasicCrosshair"
	screenGui.ResetOnSpawn = false

	local center = Instance.new("Frame")
	center.Name = "Center"
	center.Size = UDim2.new(0, 4, 0, 4)
	center.Position = UDim2.new(0.5, -2, 0.5, -2)
	center.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	center.BorderSizePixel = 0
	center.Parent = screenGui

	local lines = {
		{Name = "Top", Size = UDim2.new(0, 2, 0, 8), Position = UDim2.new(0.5, -1, 0.5, -12)},
		{Name = "Bottom", Size = UDim2.new(0, 2, 0, 8), Position = UDim2.new(0.5, -1, 0.5, 4)},
		{Name = "Left", Size = UDim2.new(0, 8, 0, 2), Position = UDim2.new(0.5, -12, 0.5, -1)},
		{Name = "Right", Size = UDim2.new(0, 8, 0, 2), Position = UDim2.new(0.5, 4, 0.5, -1)}
	}

	for _, lineData in ipairs(lines) do
		local line = Instance.new("Frame")
		line.Name = lineData.Name
		line.Size = lineData.Size
		line.Position = lineData.Position
		line.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
		line.BorderSizePixel = 0
		line.Parent = screenGui
	end

	-- Create hitmarker (hidden by default)
	for i = 1, 4 do
		local hitmarker = Instance.new("Frame")
		hitmarker.Name = "Hitmarker" .. i
		hitmarker.Size = UDim2.new(0, 10, 0, 2)
		hitmarker.BackgroundColor3 = FIRING_SETTINGS.HITMARKER_COLOR
		hitmarker.BorderSizePixel = 0
		hitmarker.Rotation = (i - 1) * 45
		hitmarker.AnchorPoint = Vector2.new(0.5, 0.5)
		hitmarker.Position = UDim2.new(0.5, 0, 0.5, 0)
		hitmarker.Visible = false
		hitmarker.Parent = screenGui
	end

	screenGui.Parent = self.player.PlayerGui
	self.crosshair = screenGui

	print("Basic crosshair created")
end

-- Set current weapon
function FiringSystem:setWeapon(weaponModel, weaponConfig)
	if not weaponModel then
		warn("Cannot set weapon: No weapon model provided")
		return false
	end

	-- Store weapon data
	self.currentWeapon = weaponModel
	self.weaponConfig = weaponConfig or {}

	-- Reset firing state
	self.isFiring = false
	self.canFire = true
	self.isReloading = false
	self.lastFireTime = 0
	self.burstCount = 0

	-- Set up ammo data if not already configured
	local weaponName = weaponModel.Name

	if not self.ammoData[weaponName] then
		local magazineSize = self.weaponConfig.magazine and self.weaponConfig.magazine.size or FIRING_SETTINGS.DEFAULT_MAGAZINE_SIZE
		local maxAmmo = self.weaponConfig.magazine and self.weaponConfig.magazine.maxAmmo or FIRING_SETTINGS.DEFAULT_RESERVE_AMMO

		self.ammoData[weaponName] = {
			magazineCurrent = magazineSize,
			reserveAmmo = maxAmmo,
			magazineSize = magazineSize
		}
	end

	print("Weapon set: " .. weaponName)
	print("Magazine: " .. self.ammoData[weaponName].magazineCurrent .. "/" .. self.ammoData[weaponName].magazineSize)
	print("Reserve: " .. self.ammoData[weaponName].reserveAmmo)

	return true
end

-- Handle firing input
function FiringSystem:handleFiring(isPressed)
	-- Update firing state
	self.isFiring = isPressed

	-- For semi-auto weapons, we only need to fire once per click
	if isPressed and self.canFire and not self.isReloading then
		local fireMode = self.weaponConfig.firingMode or FIRING_SETTINGS.FIRE_MODES.FULL_AUTO

		if fireMode == FIRING_SETTINGS.FIRE_MODES.SEMI_AUTO or
			fireMode == FIRING_SETTINGS.FIRE_MODES.BOLT_ACTION or
			fireMode == FIRING_SETTINGS.FIRE_MODES.PUMP_ACTION then

			self:fireSingle()

			-- For bolt action, we need to cycle after firing
			if fireMode == FIRING_SETTINGS.FIRE_MODES.BOLT_ACTION then
				self:performBoltAction()
			elseif fireMode == FIRING_SETTINGS.FIRE_MODES.PUMP_ACTION then
				self:performPumpAction()
			end
		elseif fireMode == FIRING_SETTINGS.FIRE_MODES.BURST then
			self:fireBurst()
		end
	end

	-- For full auto, we use the RenderStepped for continuous firing
	if isPressed and fireMode == FIRING_SETTINGS.FIRE_MODES.FULL_AUTO then
		-- If not already firing, set up the firing connection
		if not self.firingConnection then
			self.firingConnection = RunService.RenderStepped:Connect(function(dt)
				self:update(dt)
			end)
		end
	elseif not isPressed and self.firingConnection then
		-- Stop firing
		self.firingConnection:Disconnect()
		self.firingConnection = nil
	end

	return self.isFiring
end

-- Update function for continuous firing
function FiringSystem:update(dt)
	if self.isFiring and self.canFire and not self.isReloading then
		local fireMode = self.weaponConfig.firingMode or FIRING_SETTINGS.FIRE_MODES.FULL_AUTO

		if fireMode == FIRING_SETTINGS.FIRE_MODES.FULL_AUTO then
			self:fireSingle()
		end
	end
end

-- Fire a single shot
function FiringSystem:fireSingle()
	if not self.canFire or not self.currentWeapon or self.isReloading then
		return false
	end

	local ammoData = self:getAmmoData()
	if not ammoData or ammoData.magazineCurrent <= 0 then
		-- Out of ammo, play empty sound
		self:playSound("empty")

		-- Auto-reload if no ammo and have reserve
		if ammoData and ammoData.magazineCurrent <= 0 and ammoData.reserveAmmo > 0 then
			self:reload()
		end

		return false
	end

	-- Check fire rate
	local fireRate = self.weaponConfig.firerate or 600 -- Rounds per minute
	local timeBetweenShots = 60 / fireRate
	local now = tick()

	if now - self.lastFireTime < timeBetweenShots then
		return false
	end

	-- Update fire timing
	self.lastFireTime = now

	-- Decrease ammo
	ammoData.magazineCurrent = ammoData.magazineCurrent - 1

	-- Fire the bullet
	local bulletData = self:createBullet()

	-- Apply recoil
	self:applyRecoil()

	-- Create visual effects
	self:createMuzzleFlash()
	self:createShellCasing()

	-- Play fire sound
	self:playSound("fire")

	-- Notify server about shot
	self:notifyServer("fire", bulletData)

	-- For fire modes that need to block firing, set canFire to false
	local fireMode = self.weaponConfig.firingMode
	if fireMode == FIRING_SETTINGS.FIRE_MODES.BOLT_ACTION or
		fireMode == FIRING_SETTINGS.FIRE_MODES.PUMP_ACTION then
		self.canFire = false
	end

	return true
end

-- Fire a burst of shots
function FiringSystem:fireBurst()
	if not self.canFire or not self.currentWeapon or self.isReloading then
		return false
	end

	-- Get burst count from weapon config
	local burstSize = self.weaponConfig.burstCount or 3
	self.burstCount = burstSize

	-- Fire first shot immediately
	self:fireSingle()

	-- Set up delayed firing for remaining burst shots
	local fireRate = self.weaponConfig.firerate or 600
	local timeBetweenShots = 60 / fireRate

	-- Schedule the remaining shots
	for i = 2, burstSize do
		task.delay(timeBetweenShots * (i-1), function()
			if self.currentWeapon and self.burstCount > 0 then
				self:fireSingle()
				self.burstCount = self.burstCount - 1
			end
		end)
	end

	return true
end

-- Create and fire a bullet
function FiringSystem:createBullet()
	-- Get muzzle position from weapon
	local muzzleAttachment = self:getMuzzleAttachment()
	local muzzlePosition = muzzleAttachment and muzzleAttachment.WorldPosition or 
		self.camera.CFrame.Position + self.camera.CFrame.LookVector * 2

	-- Calculate direction with spread
	local direction = self:calculateFiringDirection()

	-- Get bullet velocity from weapon config
	local velocity = self.weaponConfig.velocity or FIRING_SETTINGS.DEFAULT_VELOCITY

	-- Bullet data
	local bulletData = {
		origin = muzzlePosition,
		direction = direction,
		velocity = velocity,
		damage = self.weaponConfig.damage or 25,
		penetration = self.weaponConfig.penetration or 1.0,
		bulletDrop = self.weaponConfig.bulletDrop or 0.1,
		damageRanges = self.weaponConfig.damageRanges or FIRING_SETTINGS.DEFAULT_DAMAGE_RANGES
	}

	-- Create tracer effect
	if self:shouldCreateTracer() then
		self:createTracerEffect(bulletData)
	end

	-- Simulate the bullet flight path
	local hitResult = self:simulateBullet(bulletData)

	-- Handle hit result
	if hitResult then
		-- Create impact effect
		self:createImpactEffect(hitResult)

		-- Register hit with server if it's a character
		if hitResult.isCharacter then
			self:registerHit(hitResult)
		end

		-- Show hitmarker
		if hitResult.isCharacter then
			self:showHitmarker(hitResult.isHeadshot)
		end
	end

	return bulletData
end

-- Calculate firing direction with spread
function FiringSystem:calculateFiringDirection()
	-- Base direction from camera
	local baseDirection = self.camera.CFrame.LookVector

	-- Apply spread based on weapon state
	local spreadFactor = self:calculateSpread()

	-- Add random spread
	local randomX = (math.random() - 0.5) * spreadFactor
	local randomY = (math.random() - 0.5) * spreadFactor
	local randomZ = (math.random() - 0.5) * spreadFactor

	-- Apply spread to direction
	local spreadDirection = (baseDirection + Vector3.new(randomX, randomY, randomZ)).Unit

	return spreadDirection
end

-- Calculate spread based on current state
function FiringSystem:calculateSpread()
	local baseSpread = 0.01 -- Default spread

	-- Get spread modifiers from weapon config
	if self.weaponConfig.spread then
		baseSpread = self.weaponConfig.spread.base or baseSpread

		-- Apply state-based modifiers
		if self.weaponConfig.spread.moving and self:isPlayerMoving() then
			baseSpread = baseSpread * self.weaponConfig.spread.moving
		end

		if self.weaponConfig.spread.jumping and self:isPlayerJumping() then
			baseSpread = baseSpread * self.weaponConfig.spread.jumping
		end

		-- Apply sustained fire spread if configured
		if self.weaponConfig.spread.sustained then
			local fireInterval = tick() - self.lastFireTime
			if fireInterval < 0.5 then -- If firing continuously
				local sustainedSpread = self.weaponConfig.spread.sustained
				local maxSustained = self.weaponConfig.spread.maxSustained or 2.0

				baseSpread = math.min(baseSpread + sustainedSpread, baseSpread * maxSustained)
			end
		end
	end

	-- Reduce spread when aiming
	if self.viewmodel and self.viewmodel.isAiming then
		baseSpread = baseSpread * 0.3
	end

	return baseSpread
end

-- Check if player is moving
function FiringSystem:isPlayerMoving()
	local character = self.player.Character
	if not character or not character:FindFirstChild("Humanoid") then
		return false
	end

	return character.Humanoid.MoveDirection.Magnitude > 0.1
end

-- Check if player is jumping
function FiringSystem:isPlayerJumping()
	local character = self.player.Character
	if not character or not character:FindFirstChild("Humanoid") then
		return false
	end

	return character.Humanoid:GetState() == Enum.HumanoidStateType.Jumping or
		character.Humanoid:GetState() == Enum.HumanoidStateType.Freefall
end

-- Decide whether to create a tracer
function FiringSystem:shouldCreateTracer()
	-- Check if tracers are enabled in weapon config
	if self.weaponConfig.tracers and self.weaponConfig.tracers.enabled ~= nil then
		if not self.weaponConfig.tracers.enabled then
			return false
		end

		-- Check tracer frequency (e.g., every 3rd bullet)
		local frequency = self.weaponConfig.tracers.frequency or 1
		local ammoData = self:getAmmoData()

		if ammoData then
			local shotCount = ammoData.magazineSize - ammoData.magazineCurrent
			return shotCount % frequency == 0
		end
	end

	-- Default to showing tracers
	return true
end

-- Create bullet tracer effect
function FiringSystem:createTracerEffect(bulletData)
	-- Get tracer settings from weapon config
	local tracerWidth = (self.weaponConfig.tracers and self.weaponConfig.tracers.width) or 
		FIRING_SETTINGS.BULLET_TRAIL_WIDTH

	local tracerColor = (self.weaponConfig.tracers and self.weaponConfig.tracers.color) or 
		Color3.fromRGB(255, 255, 100)

	-- Calculate start and end positions
	local startPos = bulletData.origin
	local endPos = startPos + bulletData.direction * 200 -- Show tracer for 200 studs ahead

	-- Create tracer part
	local tracer = Instance.new("Part")
	tracer.Name = "BulletTracer"
	tracer.Size = Vector3.new(tracerWidth, tracerWidth, (endPos - startPos).Magnitude)
	tracer.CFrame = CFrame.lookAt(startPos, endPos) * CFrame.new(0, 0, -tracer.Size.Z/2)
	tracer.Material = Enum.Material.Neon
	tracer.Color = tracerColor
	tracer.CanCollide = false
	tracer.Anchored = true
	tracer.Transparency = 0.2

	-- Use proper collision group
	pcall(function()
		tracer.CollisionGroup = "Bullets"
	end)

	tracer.Parent = self.effectsFolder

	-- Fade out tracer
	TweenService:Create(
		tracer,
		TweenInfo.new(FIRING_SETTINGS.BULLET_TRAIL_LIFETIME, Enum.EasingStyle.Linear),
		{Transparency = 1}
	):Play()

	-- Auto-cleanup
	Debris:AddItem(tracer, FIRING_SETTINGS.BULLET_TRAIL_LIFETIME)

	return tracer
end

-- Simulate bullet physics with advanced ballistics
function FiringSystem:simulateBullet(bulletData)
	local origin = bulletData.origin
	local direction = bulletData.direction
	local velocity = bulletData.velocity
	local penetrationPower = bulletData.penetration
	local bulletDrop = bulletData.bulletDrop

	-- Trace the bullet path in segments for accuracy
	local totalDistance = 0
	local maxDistance = 1000 -- Maximum travel distance
	local segmentLength = maxDistance / FIRING_SETTINGS.RAYCAST_RESOLUTION
	local currentPos = origin
	local penetrationsLeft = FIRING_SETTINGS.MAX_PENETRATIONS
	local lastHitPart = nil

	-- Raycast parameters
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = {self.player.Character, self.camera, self.effectsFolder}

	-- Loop through segments
	for i = 1, FIRING_SETTINGS.RAYCAST_RESOLUTION do
		-- Apply bullet drop to direction vector
		local dropFactor = bulletDrop * (i / FIRING_SETTINGS.RAYCAST_RESOLUTION)
		local currentDirection = (direction - Vector3.new(0, dropFactor, 0)).Unit

		-- Calculate segment endpoint
		local segmentEnd = currentPos + currentDirection * segmentLength

		-- Perform raycast for this segment
		local raycastResult = workspace:Raycast(currentPos, segmentEnd - currentPos, raycastParams)

		if raycastResult then
			local hitPart = raycastResult.Instance
			local hitPoint = raycastResult.Position
			local hitNormal = raycastResult.Normal
			local hitMaterial = raycastResult.Material

			-- Calculate distance traveled
			local distanceTraveled = (hitPoint - origin).Magnitude
			totalDistance = distanceTraveled

			-- Check if we hit the same part twice in a row (avoid repeated hits)
			if hitPart == lastHitPart then
				break
			end
			lastHitPart = hitPart

			-- Calculate damage based on distance
			local damage = self:calculateDamageAtDistance(bulletData.damage, distanceTraveled, bulletData.damageRanges)

			-- Check if we hit a character
			local character, humanoid, hitPlayerName, isHeadshot = self:checkCharacterHit(hitPart)

			if character and humanoid then
				-- We hit a player, return hit data
				return {
					part = hitPart,
					position = hitPoint,
					normal = hitNormal,
					material = hitMaterial,
					distance = distanceTraveled,
					damage = damage,
					isCharacter = true,
					character = character,
					humanoid = humanoid,
					playerName = hitPlayerName,
					isHeadshot = isHeadshot
				}
			else
				-- We hit environment, check for penetration
				local partThickness = self:estimatePartThickness(hitPart, hitPoint, currentDirection)
				local materialMultiplier = FIRING_SETTINGS.MATERIAL_PENETRATION[hitMaterial] or 1.0
				local canPenetrate = penetrationPower * materialMultiplier > partThickness and penetrationsLeft > 0

				if canPenetrate then
					-- Penetrate the object
					penetrationsLeft = penetrationsLeft - 1
					penetrationPower = penetrationPower * 0.7 -- Reduce penetration power
					damage = damage * 0.8 -- Reduce damage after penetration

					-- Add exit wound effect at predicted exit point
					local exitPoint = hitPoint + currentDirection * partThickness
					self:createExitWoundEffect(exitPoint, hitMaterial)

					-- Continue ray from just past the exit point
					currentPos = exitPoint + currentDirection * 0.1

					-- Skip to next segment
					continue
				else
					-- We hit something we can't penetrate
					return {
						part = hitPart,
						position = hitPoint,
						normal = hitNormal,
						material = hitMaterial,
						distance = distanceTraveled,
						damage = damage,
						isCharacter = false
					}
				end
			end
		else
			-- Update position for next segment
			currentPos = segmentEnd
		end

		-- If we've gone too far, stop simulation
		if (currentPos - origin).Magnitude > maxDistance then
			break
		end
	end

	-- If we got here, we didn't hit anything solid
	return nil
end

-- Check if a hit part belongs to a character
function FiringSystem:checkCharacterHit(hitPart)
	if not hitPart then return nil, nil, nil, false end

	-- Find character model by traversing up
	local character = hitPart
	while character and character.Parent ~= workspace do
		character = character.Parent
		if not character then break end
	end

	-- Check if it's a valid character with humanoid
	if character and character:FindFirstChildOfClass("Humanoid") then
		local humanoid = character:FindFirstChildOfClass("Humanoid")

		-- Get player name if possible
		local playerName = nil
		for _, player in pairs(Players:GetPlayers()) do
			if player.Character == character then
				playerName = player.Name
				break
			end
		end

		-- Check for headshot
		local isHeadshot = hitPart.Name == "Head"

		return character, humanoid, playerName, isHeadshot
	end

	return nil, nil, nil, false
end

-- Calculate damage based on distance
function FiringSystem:calculateDamageAtDistance(baseDamage, distance, damageRanges)
	if not damageRanges or #damageRanges == 0 then
		return baseDamage
	end

	-- Sort ranges by distance (just in case they're not already sorted)
	table.sort(damageRanges, function(a, b)
		return a.distance < b.distance
	end)

	-- Find the appropriate range
	for i = 1, #damageRanges do
		if i == #damageRanges or (distance >= damageRanges[i].distance and distance < damageRanges[i+1].distance) then
			if i == #damageRanges then
				-- Beyond the last defined range
				return baseDamage * (damageRanges[i].multiplier or damageRanges[i].damage / baseDamage)
			else
				-- Interpolate between ranges
				local rangeStart = damageRanges[i]
				local rangeEnd = damageRanges[i+1]
				local t = (distance - rangeStart.distance) / (rangeEnd.distance - rangeStart.distance)

				local startMultiplier = rangeStart.multiplier or rangeStart.damage / baseDamage
				local endMultiplier = rangeEnd.multiplier or rangeEnd.damage / baseDamage

				-- Linear interpolation
				local multiplier = startMultiplier + (endMultiplier - startMultiplier) * t
				return baseDamage * multiplier
			end
		end
	end

	-- Fallback if no range matches (shouldn't happen)
	return baseDamage
end

-- Estimate the thickness of a part for penetration calculation
function FiringSystem:estimatePartThickness(part, hitPoint, direction)
	if not part:IsA("BasePart") then return 1000 end -- Non-parts are impenetrable

	-- Cast another ray from inside the part
	local internalStartPoint = hitPoint + direction * 0.1

	-- Create a ray from inside toward outside
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Include
	raycastParams.FilterDescendantsInstances = {part}

	-- Raycast in the same direction to find exit point
	local raycastResult = workspace:Raycast(internalStartPoint, direction * part.Size.Magnitude, raycastParams)

	if raycastResult then
		-- Calculate distance between hit points
		return (raycastResult.Position - hitPoint).Magnitude
	else
		-- Fallback if raycast fails
		return part.Size.Magnitude/2 -- Rough estimate
	end
end

-- Create exit wound effect when bullet penetrates
function FiringSystem:createExitWoundEffect(position, material)
	-- Create exit wound particle effect
	local effect = Instance.new("Part")
	effect.Name = "ExitWound"
	effect.Size = Vector3.new(0.1, 0.1, 0.1)
	effect.Position = position
	effect.Anchored = true
	effect.CanCollide = false
	effect.Transparency = 1
	effect.Parent = self.effectsFolder

	-- Add particles based on material
	local particles = Instance.new("ParticleEmitter")
	particles.Enabled = false

	if material == Enum.Material.Wood then
		particles.Color = ColorSequence.new(Color3.fromRGB(150, 100, 50))
		particles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 0.3)
		})
	elseif material == Enum.Material.Concrete then
		particles.Color = ColorSequence.new(Color3.fromRGB(150, 150, 150))
		particles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 0.2)
		})
	elseif material == Enum.Material.Metal then
		particles.Color = ColorSequence.new(Color3.fromRGB(200, 200, 200))
		particles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(1, 0.1)
		})
	else
		particles.Color = ColorSequence.new(Color3.fromRGB(100, 100, 100))
		particles.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 0.2)
		})
	end

	particles.Lifetime = NumberRange.new(0.5, 1)
	particles.Speed = NumberRange.new(3, 8)
	particles.SpreadAngle = Vector2.new(30, 30)
	particles.Parent = effect

	-- Emit a burst of particles
	particles:Emit(15)

	-- Auto-cleanup
	Debris:AddItem(effect, 1)
end

-- Create shell casing effect
function FiringSystem:createShellCasing()
	-- Find shell ejection point on the weapon
	local shellPoint = self.currentWeapon.PrimaryPart:FindFirstChild("ShellEjectPoint")
	if not shellPoint then return end

	-- Create shell casing part
	local shell = Instance.new("Part")
	shell.Name = "ShellCasing"
	shell.Size = Vector3.new(0.05, 0.15, 0.05)
	shell.Position = shellPoint.WorldPosition
	shell.Color = Color3.fromRGB(200, 170, 0) -- Brass color
	shell.Material = Enum.Material.Metal
	shell.CanCollide = true
	shell.Parent = self.effectsFolder

	-- Apply physics
	shell.Velocity = shellPoint.WorldCFrame.RightVector * 5 + Vector3.new(0, 2, 0)
	shell.RotVelocity = Vector3.new(
		math.random(-20, 20),
		math.random(-20, 20),
		math.random(-20, 20)
	)

	-- Add shell collision sound
	local sound = Instance.new("Sound")
	sound.SoundId = "rbxassetid://4743758644" -- Shell casing sound
	sound.Volume = 0.2
	sound.Parent = shell

	-- Connect to Touched event to play sound when shell hits something
	local hasPlayed = false
	shell.Touched:Connect(function(hit)
		if not hasPlayed and hit:IsA("BasePart") and hit.Parent ~= self.effectsFolder then
			sound:Play()
			hasPlayed = true
		end
	end)

	-- Auto-cleanup
	Debris:AddItem(shell, FIRING_SETTINGS.SHELL_CASING_LIFETIME)
end

-- Create muzzle flash effect
function FiringSystem:createMuzzleFlash()
	-- Find muzzle attachment
	local muzzleAttachment = self:getMuzzleAttachment()
	if not muzzleAttachment then return end

	-- Get settings from weapon config
	local size = (self.weaponConfig.muzzleFlash and self.weaponConfig.muzzleFlash.size) or 1.0
	local brightness = (self.weaponConfig.muzzleFlash and self.weaponConfig.muzzleFlash.brightness) or 1.0
	local color = (self.weaponConfig.muzzleFlash and self.weaponConfig.muzzleFlash.color) or 
		Color3.fromRGB(255, 200, 100)

	-- Create flash part
	local flash = Instance.new("Part")
	flash.Name = "MuzzleFlash"
	flash.Size = Vector3.new(0.2 * size, 0.2 * size, 0.2 * size)
	flash.CFrame = muzzleAttachment.WorldCFrame
	flash.Anchored = true
	flash.CanCollide = false
	flash.Material = Enum.Material.Neon
	flash.Color = color
	flash.Transparency = 0.2
	flash.Shape = Enum.PartType.Ball
	flash.Parent = self.effectsFolder

	-- Add point light
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 5 * size
	light.Brightness = 2 * brightness
	light.Parent = flash

	-- Create fancy particles
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(color)
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.5 * size),
		NumberSequenceKeypoint.new(1, 0.1 * size)
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 1)
	})
	particles.Lifetime = NumberRange.new(0.05, 0.1)
	particles.Speed = NumberRange.new(5, 10)
	particles.SpreadAngle = Vector2.new(20, 20)
	particles.Rate = 0 -- We'll emit once
	particles.Parent = flash

	-- Emit a burst of particles
	particles:Emit(10)

	-- Auto-cleanup after a short duration
	Debris:AddItem(flash, FIRING_SETTINGS.MUZZLE_FLASH_DURATION)

	-- Fade out the flash
	TweenService:Create(
		flash,
		TweenInfo.new(FIRING_SETTINGS.MUZZLE_FLASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Transparency = 1, Size = flash.Size * 2}
	):Play()

	-- Fade out the light
	TweenService:Create(
		light,
		TweenInfo.new(FIRING_SETTINGS.MUZZLE_FLASH_DURATION, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{Brightness = 0, Range = 0}
	):Play()
end

-- Create impact effect
function FiringSystem:createImpactEffect(hitInfo)
	local position = hitInfo.position
	local normal = hitInfo.normal
	local material = hitInfo.material

	-- Create impact base part
	local impact = Instance.new("Part")
	impact.Name = "BulletImpact"
	impact.Size = Vector3.new(0.1, 0.1, 0.1)
	impact.CFrame = CFrame.lookAt(position + normal * 0.05, position + normal)
	impact.Anchored = true
	impact.CanCollide = false
	impact.Transparency = 1
	impact.Parent = self.effectsFolder

	-- Create different effects based on material
	if hitInfo.isCharacter then
		-- Blood effect for characters
		self:createBloodEffect(impact)
	elseif material == Enum.Material.Concrete or material == Enum.Material.Slate or material == Enum.Material.Brick then
		-- Concrete impact
		self:createConcreteEffect(impact)
	elseif material == Enum.Material.Metal or material == Enum.Material.CorrodedMetal or material == Enum.Material.DiamondPlate then
		-- Metal impact
		self:createMetalEffect(impact)
	elseif material == Enum.Material.Wood or material == Enum.Material.WoodPlanks then
		-- Wood impact
		self:createWoodEffect(impact)
	elseif material == Enum.Material.Glass or material == Enum.Material.ForceField then
		-- Glass impact
		self:createGlassEffect(impact)
	else
		-- Generic impact
		self:createGenericEffect(impact)
	end

	-- Play impact sound based on material
	self:playImpactSound(material, position)

	-- Auto-cleanup
	Debris:AddItem(impact, 3)
end

-- Create blood effect for character hits
function FiringSystem:createBloodEffect(parentPart)
	-- Blood particle emitter
	local blood = Instance.new("ParticleEmitter")
	blood.Color = ColorSequence.new(Color3.fromRGB(150, 0, 0))
	blood.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 0.05)
	})
	blood.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.5),
		NumberSequenceKeypoint.new(1, 1)
	})
	blood.Lifetime = NumberRange.new(0.5, 0.8)
	blood.Speed = NumberRange.new(3, 6)
	blood.SpreadAngle = Vector2.new(35, 35)
	blood.Rate = 0
	blood.Parent = parentPart

	-- Emit particles
	blood:Emit(20)

	-- Create blood decal that fades away
	local bloodDecal = Instance.new("Decal")
	bloodDecal.Texture = "rbxassetid://2454288500" -- Blood splatter texture
	bloodDecal.Face = Enum.NormalId.Front
	bloodDecal.Parent = parentPart

	-- Animate blood decal
	TweenService:Create(
		bloodDecal,
		TweenInfo.new(2, Enum.EasingStyle.Linear),
		{Transparency = 1}
	):Play()
end

-- Create concrete impact effect
function FiringSystem:createConcreteEffect(parentPart)
	-- Dust particle emitter
	local dust = Instance.new("ParticleEmitter")
	dust.Color = ColorSequence.new(Color3.fromRGB(150, 150, 150))
	dust.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.5, 0.1),
		NumberSequenceKeypoint.new(1, 0.15)
	})
	dust.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.6),
		NumberSequenceKeypoint.new(1, 1)
	})
	dust.Lifetime = NumberRange.new(0.5, 1)
	dust.Speed = NumberRange.new(2, 5)
	dust.SpreadAngle = Vector2.new(40, 40)
	dust.Rate = 0
	dust.Parent = parentPart

	-- Emit particles
	dust:Emit(15)

	-- Create impact decal
	local impactDecal = Instance.new("Decal")
	impactDecal.Texture = "rbxassetid://2454288026" -- Bullet hole texture
	impactDecal.Face = Enum.NormalId.Front
	impactDecal.Parent = parentPart

	-- Animate decal
	TweenService:Create(
		impactDecal,
		TweenInfo.new(3, Enum.EasingStyle.Linear),
		{Transparency = 1}
	):Play()
end

-- Create metal impact effect
function FiringSystem:createMetalEffect(parentPart)
	-- Spark particle emitter
	local sparks = Instance.new("ParticleEmitter")
	sparks.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 100)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 100, 0))
	})
	sparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.03),
		NumberSequenceKeypoint.new(0.5, 0.02),
		NumberSequenceKeypoint.new(1, 0.01)
	})
	sparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.5),
		NumberSequenceKeypoint.new(1, 1)
	})
	sparks.Lifetime = NumberRange.new(0.2, 0.4)
	sparks.Speed = NumberRange.new(5, 10)
	sparks.SpreadAngle = Vector2.new(50, 50)
	sparks.Rate = 0
	sparks.Acceleration = Vector3.new(0, -10, 0)
	sparks.Parent = parentPart

	-- Emit particles
	sparks:Emit(30)

	-- Create impact decal
	local impactDecal = Instance.new("Decal")
	impactDecal.Texture = "rbxassetid://2454288026" -- Bullet hole texture
	impactDecal.Face = Enum.NormalId.Front
	impactDecal.Parent = parentPart

	-- Animate decal
	TweenService:Create(
		impactDecal,
		TweenInfo.new(3, Enum.EasingStyle.Linear),
		{Transparency = 1}
	):Play()
end

-- Create wood impact effect
function FiringSystem:createWoodEffect(parentPart)
	-- Wood particle emitter
	local woodChips = Instance.new("ParticleEmitter")
	woodChips.Color = ColorSequence.new(Color3.fromRGB(150, 100, 50))
	woodChips.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 0.02)
	})
	woodChips.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.5),
		NumberSequenceKeypoint.new(1, 1)
	})
	woodChips.Lifetime = NumberRange.new(0.5, 1)
	woodChips.Speed = NumberRange.new(3, 6)
	woodChips.SpreadAngle = Vector2.new(35, 35)
	woodChips.Rate = 0
	woodChips.Parent = parentPart

	-- Emit particles
	woodChips:Emit(20)

	-- Create impact decal
	local impactDecal = Instance.new("Decal")
	impactDecal.Texture = "rbxassetid://2454288026" -- Bullet hole texture
	impactDecal.Face = Enum.NormalId.Front
	impactDecal.Color3 = Color3.fromRGB(70, 50, 30)
	impactDecal.Parent = parentPart

	-- Animate decal
	TweenService:Create(
		impactDecal,
		TweenInfo.new(3, Enum.EasingStyle.Linear),
		{Transparency = 1}
	):Play()
end

-- Create glass impact effect
function FiringSystem:createGlassEffect(parentPart)
	-- Glass particle emitter
	local glassShards = Instance.new("ParticleEmitter")
	glassShards.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255))
	glassShards.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.04),
		NumberSequenceKeypoint.new(1, 0.01)
	})
	glassShards.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.8, 0.5),
		NumberSequenceKeypoint.new(1, 1)
	})
	glassShards.Lifetime = NumberRange.new(0.5, 1)
	glassShards.Speed = NumberRange.new(4, 8)
	glassShards.SpreadAngle = Vector2.new(45, 45)
	glassShards.Rate = 0
	glassShards.Parent = parentPart

	-- Emit particles
	glassShards:Emit(25)

	-- Create crack decal
	local crackDecal = Instance.new("Decal")
	crackDecal.Texture = "rbxassetid://2454288026" -- Glass crack texture
	crackDecal.Face = Enum.NormalId.Front
	crackDecal.Transparency = 0.3
	crackDecal.Parent = parentPart

	-- Animate decal
	TweenService:Create(
		crackDecal,
		TweenInfo.new(2, Enum.EasingStyle.Linear),
		{Transparency = 1}
	):Play()
end

-- Create generic impact effect
function FiringSystem:createGenericEffect(parentPart)
	-- Basic particle emitter
	local particles = Instance.new("ParticleEmitter")
	particles.Color = ColorSequence.new(Color3.fromRGB(150, 150, 150))
	particles.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 0.01)
	})
	particles.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.6),
		NumberSequenceKeypoint.new(1, 1)
	})
	particles.Lifetime = NumberRange.new(0.3, 0.6)
	particles.Speed = NumberRange.new(2, 4)
	particles.SpreadAngle = Vector2.new(30, 30)
	particles.Rate = 0
	particles.Parent = parentPart

	-- Emit particles
	particles:Emit(10)

	-- Create impact decal
	local impactDecal = Instance.new("Decal")
	impactDecal.Texture = "rbxassetid://2454288026" -- Bullet hole texture
	impactDecal.Face = Enum.NormalId.Front
	impactDecal.Parent = parentPart

	-- Animate decal
	TweenService:Create(
		impactDecal,
		TweenInfo.new(2, Enum.EasingStyle.Linear),
		{Transparency = 1}
	):Play()
end

-- Play impact sound based on material
function FiringSystem:playImpactSound(material, position)
	local soundId = "rbxassetid://142082167" -- Default impact sound
	local volume = 0.5

	-- Set sound based on material
	if material == Enum.Material.Concrete or material == Enum.Material.Slate or material == Enum.Material.Brick then
		soundId = "rbxassetid://142082167" -- Concrete impact
	elseif material == Enum.Material.Metal or material == Enum.Material.CorrodedMetal or material == Enum.Material.DiamondPlate then
		soundId = "rbxassetid://142082170" -- Metal impact
	elseif material == Enum.Material.Wood or material == Enum.Material.WoodPlanks then
		soundId = "rbxassetid://142082144" -- Wood impact
	elseif material == Enum.Material.Glass or material == Enum.Material.ForceField then
		soundId = "rbxassetid://142082166" -- Glass impact
	end

	-- Create sound at impact position
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume = volume
	sound.RollOffMaxDistance = 100
	sound.RollOffMinDistance = 10
	sound.RollOffMode = Enum.RollOffMode.LinearSquare

	-- Create temporary part to play sound
	local soundPart = Instance.new("Part")
	soundPart.Size = Vector3.new(0.1, 0.1, 0.1)
	soundPart.Position = position
	soundPart.Anchored = true
	soundPart.CanCollide = false
	soundPart.Transparency = 1
	soundPart.Parent = self.effectsFolder

	sound.Parent = soundPart
	sound:Play()

	-- Auto-cleanup
	Debris:AddItem(soundPart, 3)
end

-- Apply recoil to viewmodel and camera
function FiringSystem:applyRecoil()
	-- Get recoil settings from weapon config
	local recoilVertical = (self.weaponConfig.recoil and self.weaponConfig.recoil.vertical) or 1.2
	local recoilHorizontal = (self.weaponConfig.recoil and self.weaponConfig.recoil.horizontal) or 0.3
	local recoilRecovery = (self.weaponConfig.recoil and self.weaponConfig.recoil.recovery) or 0.95

	-- Apply multiplier for ADS
	if self.viewmodel and self.viewmodel.isAiming then
		recoilVertical = recoilVertical * 0.7
		recoilHorizontal = recoilHorizontal * 0.7
	end

	-- Add randomness to recoil direction
	local randomHorizontal = (math.random() - 0.5) * recoilHorizontal

	-- Apply recoil to viewmodel
	if self.viewmodel and typeof(self.viewmodel.addRecoil) == "function" then
		self.viewmodel:addRecoil(recoilVertical * 0.05, randomHorizontal * 0.05)
	end

	-- Apply recoil to camera system if available
	local cameraSystem = _G.FPSCameraSystem
	if cameraSystem and typeof(cameraSystem.addRecoil) == "function" then
		cameraSystem:addRecoil(recoilVertical, randomHorizontal)
	end

	-- Trigger crosshair spread
	if self.crosshair then
		local spreadLines = {
			"Top", "Bottom", "Left", "Right"
		}

		-- Temporarily increase crosshair spread
		local originalPositions = {}
		for _, lineName in ipairs(spreadLines) do
			local line = self.crosshair:FindFirstChild(lineName)
			if line then
				originalPositions[lineName] = line.Position

				-- Move line outward
				local direction = line.Position - UDim2.new(0.5, 0, 0.5, 0)
				line.Position = line.Position + direction * 0.5

				-- Animate back to original position
				TweenService:Create(
					line,
					TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{Position = originalPositions[lineName]}
				):Play()
			end
		end
	end
end

-- Perform animation for bolt-action weapons
function FiringSystem:performBoltAction()
	if not self.currentWeapon then return end

	-- Play bolt cycling animation
	-- This would normally be an animation, but we'll simulate it with a simple movement

	-- Find bolt part if it exists
	local bolt = self.currentWeapon:FindFirstChild("Bolt")
	if bolt and bolt:IsA("BasePart") then
		-- Store original position
		local originalCFrame = bolt.CFrame

		-- Move bolt back
		local backCFrame = originalCFrame * CFrame.new(0, 0, 0.3)
		TweenService:Create(
			bolt,
			TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{CFrame = backCFrame}
		):Play()

		-- After a delay, move bolt forward
		task.delay(0.2, function()
			TweenService:Create(
				bolt,
				TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{CFrame = originalCFrame}
			):Play()

			-- Enable firing again
			task.delay(0.15, function()
				self.canFire = true
			end)
		end)
	else
		-- If no bolt part, just wait for animation time
		task.delay(0.5, function()
			self.canFire = true
		end)
	end

	-- Play bolt action sound
	self:playSound("boltAction")

	-- Eject shell after bolt is pulled back
	task.delay(0.15, function()
		self:createShellCasing()
	end)
end

-- Perform animation for pump-action weapons
function FiringSystem:performPumpAction()
	if not self.currentWeapon then return end

	-- Find pump part if it exists
	local pump = self.currentWeapon:FindFirstChild("Pump") or self.currentWeapon:FindFirstChild("Forestock")
	if pump and pump:IsA("BasePart") then
		-- Store original position
		local originalCFrame = pump.CFrame

		-- Move pump back
		local backCFrame = originalCFrame * CFrame.new(0, 0, 0.4)
		TweenService:Create(
			pump,
			TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{CFrame = backCFrame}
		):Play()

		-- After a delay, move pump forward
		task.delay(0.3, function()
			TweenService:Create(
				pump,
				TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{CFrame = originalCFrame}
			):Play()

			-- Enable firing again
			task.delay(0.2, function()
				self.canFire = true
			end)
		end)
	else
		-- If no pump part, just wait for animation time
		task.delay(0.7, function()
			self.canFire = true
		end)
	end

	-- Play pump action sound
	self:playSound("pump")

	-- Eject shell after pump is pulled back
	task.delay(0.2, function()
		self:createShellCasing()
	end)
end

-- Handle reload action
function FiringSystem:reload()
	if self.isReloading or not self.currentWeapon then return false end

	local ammoData = self:getAmmoData()
	if not ammoData or ammoData.magazineCurrent >= ammoData.magazineSize or ammoData.reserveAmmo <= 0 then
		return false
	end

	-- Start reload process
	self.isReloading = true

	-- Get reload time from config
	local reloadTime = 0

	-- Check if magazine is empty (affects reload time)
	local emptyReload = ammoData.magazineCurrent <= 0

	if self.weaponConfig.magazine then
		if emptyReload and self.weaponConfig.magazine.reloadTimeEmpty then
			reloadTime = self.weaponConfig.magazine.reloadTimeEmpty
		else
			reloadTime = self.weaponConfig.magazine.reloadTime or FIRING_SETTINGS.DEFAULT_RELOAD_TIME
		end
	else
		reloadTime = FIRING_SETTINGS.DEFAULT_RELOAD_TIME
	end

	-- Play reload sound
	if emptyReload then
		self:playSound("reloadEmpty")
	else
		self:playSound("reload")
	end

	-- Notify server about reload
	self:notifyServer("reload")

	-- After reload time, update ammo
	task.delay(reloadTime, function()
		-- Make sure weapon hasn't changed during reload
		if self.currentWeapon and self.currentWeapon.Name == weaponName then
			-- Calculate ammo to add
			local neededAmmo = ammoData.magazineSize - ammoData.magazineCurrent
			local ammoToAdd = math.min(neededAmmo, ammoData.reserveAmmo)

			-- Update ammo counts
			ammoData.magazineCurrent = ammoData.magazineCurrent + ammoToAdd
			ammoData.reserveAmmo = ammoData.reserveAmmo - ammoToAdd

			-- End reload state
			self.isReloading = false

			print("Reload complete. Magazine: " .. ammoData.magazineCurrent .. 
				"/" .. ammoData.magazineSize .. ", Reserve: " .. ammoData.reserveAmmo)
		end
	end)

	return true
end

-- Get current ammo data
function FiringSystem:getAmmoData()
	if not self.currentWeapon then return nil end
	return self.ammoData[self.currentWeapon.Name]
end

-- Get muzzle attachment from weapon
function FiringSystem:getMuzzleAttachment()
	if not self.currentWeapon then return nil end

	-- Look for muzzle attachment on the weapon
	for _, part in ipairs(self.currentWeapon:GetDescendants()) do
		if part:IsA("BasePart") and part.Name == "Barrel" then
			local muzzle = part:FindFirstChild("MuzzlePoint")
			if muzzle and muzzle:IsA("Attachment") then
				return muzzle
			end
		end
	end

	-- Try main attachment point on PrimaryPart
	if self.currentWeapon.PrimaryPart then
		local muzzle = self.currentWeapon.PrimaryPart:FindFirstChild("MuzzlePoint")
		if muzzle and muzzle:IsA("Attachment") then
			return muzzle
		end
	end

	return nil
end

-- Show hitmarker when hitting a target
function FiringSystem:showHitmarker(isHeadshot)
	-- Update hitmarker color
	local hitmarkerColor = isHeadshot and 
		FIRING_SETTINGS.HITMARKER_HEADSHOT_COLOR or 
		FIRING_SETTINGS.HITMARKER_COLOR

	-- Get hitmarker lines
	for i = 1, 4 do
		local hitmarker = self.crosshair:FindFirstChild("Hitmarker" .. i)
		if hitmarker then
			-- Set color and show hitmarker
			hitmarker.BackgroundColor3 = hitmarkerColor
			hitmarker.Visible = true

			-- Hide after duration
			task.delay(FIRING_SETTINGS.HITMARKER_DURATION, function()
				hitmarker.Visible = false
			end)
		end
	end

	-- Play hitmarker sound
	local sound = Instance.new("Sound")
	sound.SoundId = isHeadshot and 
		"rbxassetid://5043539486" or -- Headshot sound
		"rbxassetid://5043539486"    -- Regular hit sound
	sound.Volume = 0.5
	sound.Parent = self.player.PlayerGui
	sound:Play()

	-- Auto-cleanup
	Debris:AddItem(sound, 1)
end

-- Register hit with server
function FiringSystem:registerHit(hitInfo)
	if not self.hitRegEvent then return end

	-- Create hit data for server
	local hitData = {
		weapon = self.currentWeapon.Name,
		damage = hitInfo.damage,
		position = hitInfo.position,
		distance = hitInfo.distance,
		part = hitInfo.part.Name,
		isHeadshot = hitInfo.isHeadshot
	}

	-- Send hit registration to server
	self.hitRegEvent:FireServer(hitInfo.character, hitData)
end

-- Notify server about weapon actions
function FiringSystem:notifyServer(action, data)
	if action == "fire" and self.weaponFiredEvent then
		self.weaponFiredEvent:FireServer(self.currentWeapon.Name, data)
	elseif action == "reload" and self.reloadEvent then
		self.reloadEvent:FireServer(self.currentWeapon.Name)
	end
end

-- Play weapon sound
function FiringSystem:playSound(soundType)
	if not self.currentWeapon then return end

	-- Get sound ID from weapon config
	local soundId
	if self.weaponConfig.sounds and self.weaponConfig.sounds[soundType] then
		soundId = self.weaponConfig.sounds[soundType]
	else
		-- Default sounds
		local defaultSounds = {
			fire = "rbxassetid://165946507",
			reload = "rbxassetid://6805664397",
			reloadEmpty = "rbxassetid://6842081192",
			empty = "rbxassetid://3744371342",
			boltAction = "rbxassetid://1753796472",
			pump = "rbxassetid://255061183"
		}

		soundId = defaultSounds[soundType]
	end

	if not soundId then return end

	-- Create sound
	local sound = Instance.new("Sound")
	sound.SoundId = soundId

	-- Set sound properties based on type
	if soundType == "fire" then
		sound.Volume = 1
		sound.RollOffMaxDistance = 500
		sound.RollOffMinDistance = 20
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
	elseif soundType == "reload" or soundType == "reloadEmpty" then
		sound.Volume = 0.8
		sound.RollOffMaxDistance = 20
		sound.RollOffMinDistance = 5
	elseif soundType == "empty" then
		sound.Volume = 0.5
	elseif soundType == "boltAction" or soundType == "pump" then
		sound.Volume = 0.7
		sound.RollOffMaxDistance = 30
		sound.RollOffMinDistance = 5
	end

	-- Apply sound modifiers from attachments
	if self.weaponConfig.soundEffects and self.weaponConfig.soundEffects.volume then
		sound.Volume = sound.Volume * self.weaponConfig.soundEffects.volume
	end

	-- Find appropriate parent for sound
	if soundType == "fire" then
		-- Fire sound comes from muzzle
		local muzzleAttachment = self:getMuzzleAttachment()
		if muzzleAttachment then
			sound.Parent = muzzleAttachment.Parent
		else
			sound.Parent = self.currentWeapon.PrimaryPart
		end
	else
		-- Other sounds come from weapon body
		sound.Parent = self.currentWeapon.PrimaryPart
	end

	-- Play the sound
	sound:Play()

	-- Auto-cleanup after sound finishes
	if sound.TimeLength > 0 then
		Debris:AddItem(sound, sound.TimeLength + 0.1)
	else
		Debris:AddItem(sound, 3) -- Default cleanup time if TimeLength not available
	end

	return sound
end

-- Clean up
function FiringSystem:cleanup()
	-- Disconnect firing connection
	if self.firingConnection then
		self.firingConnection:Disconnect()
		self.firingConnection = nil
	end

	-- Clean up effects folder
	if self.effectsFolder then
		self.effectsFolder:Destroy()
	end

	-- Clean up crosshair
	if self.crosshair then
		self.crosshair:Destroy()
	end

	print("FiringSystem cleaned up")
end

return FiringSystem