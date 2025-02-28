-- ViewmodelSystem.lua
-- Enhanced first-person viewmodel system with attachment support
-- Place in ReplicatedStorage.FPSSystem.Modules

local ViewmodelSystem = {}
ViewmodelSystem.__index = ViewmodelSystem

-- Services
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Constants
local VIEWMODEL_SETTINGS = {
	-- Positioning settings
	DEFAULT_POSITION = Vector3.new(0.20, -0.25, -0.65),
	ADS_POSITION = Vector3.new(0, -0.1, -0.4),
	SPRINT_POSITION = Vector3.new(0.4, -0.2, -0.6),

	-- Offset for different weapon types
	WEAPON_OFFSETS = {
		PRIMARY = CFrame.new(0.26, -0.15, -0.1),
		SECONDARY = CFrame.new(0.22, -0.15, -0.05),
		MELEE = CFrame.new(0.3, -0.2, 0),
		GRENADES = CFrame.new(0.26, -0.25, -0.1)
	},

	-- Sway settings
	SWAY = {
		AMOUNT = 0.05,
		SPEED = 6,
		SMOOTHING = 0.3
	},

	-- Bob settings
	BOB = {
		AMOUNT = 0.05,
		SPEED = 8,
		SPRINT_MULTIPLIER = 1.5
	},

	-- Recoil settings
	RECOIL = {
		RECOVERY_SPEED = 10
	},

	-- Animation settings
	ANIM = {
		ADS_SPEED = 0.2, -- Time to aim down sights
		EQUIP_SPEED = 0.3 -- Time to equip weapon
	}
}

-- Instance tracking to prevent duplicates
local activeInstances = {}

-- Create a new ViewmodelSystem
function ViewmodelSystem.new()
	local player = Players.LocalPlayer

	-- Check for existing instance and clean it up
	if activeInstances[player] then
		activeInstances[player]:cleanup()
	end

	local self = setmetatable({}, ViewmodelSystem)

	-- Core components
	self.camera = workspace.CurrentCamera
	self.container = nil  -- Will be created in setupContainer
	self.viewmodelRig = nil  -- Will be created in setupArms
	self.currentWeapon = nil

	-- State tracking
	self.isAiming = false
	self.isSprinting = false
	self.isMoving = false
	self.lastMouseDelta = Vector2.new()
	self.currentSway = Vector3.new()
	self.currentRecoil = Vector3.new()
	self.bobCycle = 0

	-- Create the container
	self:createViewmodelContainer()

	-- Store offsets for different states
	self.Offsets = {
		DEFAULT = {
			Position = VIEWMODEL_SETTINGS.DEFAULT_POSITION,
			Rotation = Vector3.new(0, 0, 0)
		},
		ADS = {
			Position = VIEWMODEL_SETTINGS.ADS_POSITION,
			Rotation = Vector3.new(0, 0, 0)
		},
		SPRINT = {
			Position = VIEWMODEL_SETTINGS.SPRINT_POSITION,
			Rotation = Vector3.new(-0.3, 0.4, 0.2)
		}
	}

	-- Store this instance
	activeInstances[player] = self

	-- Make globally accessible for other systems
	_G.CurrentViewmodelSystem = self

	print("ViewmodelSystem initialized")
	return self
end

-- Create the container that holds viewmodel elements
function ViewmodelSystem:createViewmodelContainer()
	-- Check for existing container
	local existingContainer = self.camera:FindFirstChild("ViewmodelContainer")
	if existingContainer then
		print("Using existing ViewmodelContainer")
		self.container = existingContainer
		return existingContainer
	end

	print("Creating new ViewmodelContainer")
	local container = Instance.new("Model")
	container.Name = "ViewmodelContainer"

	-- Create root part for positioning
	local root = Instance.new("Part")
	root.Name = "ViewmodelRoot"
	root.Size = Vector3.new(0.1, 0.1, 0.1)
	root.Transparency = 1
	root.CanCollide = false
	root.Anchored = true
	root.CFrame = self.camera.CFrame * CFrame.new(VIEWMODEL_SETTINGS.DEFAULT_POSITION)

	-- Add attachment for weapon positioning
	local weaponAttachment = Instance.new("Attachment")
	weaponAttachment.Name = "WeaponAttachment"
	weaponAttachment.CFrame = CFrame.new(0, 0, 0)
	weaponAttachment.Parent = root

	root.Parent = container
	container.PrimaryPart = root
	container.Parent = self.camera
	self.container = container

	return container
end

-- Fix transparency and collision issues for viewmodel parts
function ViewmodelSystem:fixPartProperties(part)
	if not part or not part:IsA("BasePart") then return end

	-- Handle non-visual parts
	if part.Name == "HandControl" or part.Name == "HumanoidRootPart" or part.Name == "FakeCamera" then
		part.Transparency = 1
		part.CanCollide = false
		return
	end

	-- Handle arm and hand parts
	if part.Name == "LeftArm" or part.Name == "RightArm" or
		part.Name == "LeftHand" or part.Name == "RightHand" or
		part.Name:find("Arm") or part.Name:find("Hand") then

		part.Transparency = 0
		part.LocalTransparencyModifier = 0

		-- Set default skin tone if needed
		if part.Color == Color3.new(1, 1, 1) then
			part.Color = Color3.fromRGB(255, 213, 170) -- Default skin tone
		end

		if part.Material == Enum.Material.Plastic then
			part.Material = Enum.Material.SmoothPlastic
		end
	end

	-- Set up common properties for all parts
	part.Anchored = true
	part.CanCollide = false

	-- Set up collision group to prevent interaction with character
	pcall(function()
		part.CollisionGroup = "ViewmodelNoCollision"
	end)
end

-- Set up the arms and hands
function ViewmodelSystem:setupArms(customArmsModel)
	print("Setting up viewmodel arms...")

	-- Clean up existing viewmodel
	if self.viewmodelRig then
		self.viewmodelRig:Destroy()
		self.viewmodelRig = nil
	end

	-- Ensure container exists
	if not self.container then
		self:createViewmodelContainer()
	end

	-- Load arms in order of priority:
	-- 1. Custom arms passed to function
	-- 2. Arms from ReplicatedStorage.FPSSystem.ViewModels.Arms
	-- 3. Default fallback arms

	local armsModel = nil

	-- Option 1: Custom arms passed to function
	if customArmsModel and customArmsModel:IsA("Model") then
		armsModel = customArmsModel:Clone()
		print("Using provided custom arms model")
	else
		-- Option 2: Check for arms in standard location
		local fpsSystem = ReplicatedStorage:FindFirstChild("FPSSystem")
		if fpsSystem then
			local viewModels = fpsSystem:FindFirstChild("ViewModels")
			if viewModels then
				local arms = viewModels:FindFirstChild("Arms")
				if arms then
					local viewmodelRig = arms:FindFirstChild("ViewmodelRig") or arms:FindFirstChild("VMArms")
					if viewmodelRig then
						armsModel = viewmodelRig:Clone()
						print("Using arms from FPSSystem/ViewModels/Arms")
					end
				end
			end
		end
	end

	-- Option 3: If no arms found, create default arms
	if not armsModel then
		print("No existing arms found, creating default arms")
		armsModel = self:createDefaultArms()
	end

	-- Setup the arms model
	self.viewmodelRig = armsModel
	self.viewmodelRig.Name = "ViewmodelRig"

	-- Fix transparency and attachment issues
	for _, part in ipairs(self.viewmodelRig:GetDescendants()) do
		if part:IsA("BasePart") then
			self:fixPartProperties(part)
		end
	end

	-- Position the arms at the container
	if self.container and self.container.PrimaryPart then
		pcall(function()
			self.viewmodelRig:PivotTo(self.container.PrimaryPart.CFrame)
		end)
		self.viewmodelRig.Parent = self.container
	else
		warn("Cannot position viewmodel rig: container or primaryPart is nil")
	end

	-- Watch for new parts being added
	self.partAddedConnection = self.viewmodelRig.DescendantAdded:Connect(function(descendant)
		if descendant:IsA("BasePart") then
			self:fixPartProperties(descendant)
		end
	end)

	print("Arms setup complete")
	return self.viewmodelRig
end

-- Create default arms when no model is available
function ViewmodelSystem:createDefaultArms()
	print("Creating default placeholder arms")

	local arms = Instance.new("Model")
	arms.Name = "DefaultArms"

	-- Create parts for the arms
	local parts = {
		LeftArm = {
			Size = Vector3.new(0.25, 0.8, 0.25),
			Position = Vector3.new(-0.4, -0.3, -0.2)
		},
		RightArm = {
			Size = Vector3.new(0.25, 0.8, 0.25),
			Position = Vector3.new(0.4, -0.3, -0.2)
		},
		LeftHand = {
			Size = Vector3.new(0.25, 0.25, 0.25),
			Position = Vector3.new(-0.4, -0.8, -0.2)
		},
		RightHand = {
			Size = Vector3.new(0.25, 0.25, 0.25),
			Position = Vector3.new(0.4, -0.8, -0.2)
		}
	}

	for name, data in pairs(parts) do
		local part = Instance.new("Part")
		part.Name = name
		part.Size = data.Size
		part.Position = data.Position
		part.Color = Color3.fromRGB(255, 213, 170) -- Skin tone
		part.Transparency = 0
		part.CanCollide = false
		part.Anchored = true
		part.Parent = arms

		-- Add attachment points for weapon grips
		if name == "RightHand" then
			local grip = Instance.new("Attachment")
			grip.Name = "RightGripAttachment"
			grip.CFrame = CFrame.new(0, 0, 0)
			grip.Parent = part
		elseif name == "LeftHand" then
			local grip = Instance.new("Attachment")
			grip.Name = "LeftGripAttachment"
			grip.CFrame = CFrame.new(0, 0, 0)
			grip.Parent = part
		end
	end

	return arms
end

-- Equip a weapon to the viewmodel
function ViewmodelSystem:equipWeapon(weaponModel, slot)
	if not self.viewmodelRig then
		warn("Cannot equip weapon - no viewmodel rig is set up")
		self:setupArms()
	end

	print("Equipping weapon:", weaponModel and weaponModel.Name or "nil")

	-- Clean up existing weapon if any
	if self.currentWeapon then
		self.currentWeapon:Destroy()
		self.currentWeapon = nil
	end

	-- If no weapon provided, create placeholder
	if not weaponModel then
		self:createPlaceholderWeapon(slot)
		return
	end

	-- Clone the weapon model
	local weapon = weaponModel:Clone()
	self.currentWeapon = weapon

	-- Process weapon parts
	for _, part in pairs(weapon:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Anchored = true

			-- Set collision group
			pcall(function()
				part.CollisionGroup = "ViewmodelNoCollision"
			end)
		end
	end

	-- Ensure the model has a primary part
	if not weapon.PrimaryPart then
		local primaryPart = weapon:FindFirstChild("Handle") or
			weapon:FindFirstChild("Gun") or
			weapon:FindFirstChildWhichIsA("BasePart")

		if primaryPart then
			weapon.PrimaryPart = primaryPart
		else
			warn("Weapon model needs a primary part")
			self:createPlaceholderWeapon(slot)
			return
		end
	end

	-- Parent to viewmodel
	weapon.Parent = self.viewmodelRig

	-- Wait a frame for parenting to complete
	RunService.RenderStepped:Wait()

	-- Position the weapon based on its type
	local weaponOffset = VIEWMODEL_SETTINGS.WEAPON_OFFSETS[slot] or VIEWMODEL_SETTINGS.WEAPON_OFFSETS.PRIMARY

	-- Try to use attachment points if available
	local rightHand = self.viewmodelRig:FindFirstChild("RightHand") or self.viewmodelRig:FindFirstChild("RightArm")
	local leftHand = self.viewmodelRig:FindFirstChild("LeftHand") or self.viewmodelRig:FindFirstChild("LeftArm")

	local rightGripAttachment = rightHand and rightHand:FindFirstChild("RightGripAttachment")
	local rightGripPoint = weapon.PrimaryPart:FindFirstChild("RightGripPoint")

	if rightGripAttachment and rightGripPoint then
		-- Use attachments to position weapon precisely
		local rightGripAttachmentWorld = rightGripAttachment.WorldCFrame
		local rightGripPointWorld = rightGripPoint.WorldCFrame

		-- Calculate the offset needed to align the grip points
		local offset = rightGripPointWorld:ToObjectSpace(rightGripAttachmentWorld)

		-- Position the weapon
		weapon:SetPrimaryPartCFrame(weapon.PrimaryPart.CFrame * offset)
	else
		-- Fall back to standard positioning
		if self.container and self.container.PrimaryPart then
			local containerCFrame = self.container.PrimaryPart.CFrame
			weapon:SetPrimaryPartCFrame(containerCFrame * weaponOffset)
		end
	end

	-- Play equip animation
	self:playEquipAnimation()

	print("Weapon equipped successfully")
end

-- Create a placeholder weapon
function ViewmodelSystem:createPlaceholderWeapon(slot)
	print("Creating placeholder weapon for slot:", slot)

	local weapon = Instance.new("Model")
	weapon.Name = "PlaceholderWeapon_" .. (slot or "PRIMARY")

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Anchored = true
	handle.CanCollide = false

	-- Configure based on slot
	if slot == "PRIMARY" then
		handle.Size = Vector3.new(0.4, 0.3, 2)
		handle.Color = Color3.fromRGB(80, 80, 80)

		-- Add barrel
		local barrel = Instance.new("Part")
		barrel.Name = "Barrel"
		barrel.Size = Vector3.new(0.2, 0.2, 1)
		barrel.Anchored = true
		barrel.CanCollide = false
		barrel.Color = Color3.fromRGB(60, 60, 60)
		barrel.CFrame = handle.CFrame * CFrame.new(0, 0, -handle.Size.Z/2 - barrel.Size.Z/2)
		barrel.Parent = weapon

		-- Add muzzle attachment
		local muzzle = Instance.new("Attachment")
		muzzle.Name = "MuzzlePoint"
		muzzle.Position = Vector3.new(0, 0, -barrel.Size.Z/2)
		muzzle.Parent = barrel
	elseif slot == "SECONDARY" then
		handle.Size = Vector3.new(0.3, 0.8, 0.2)
		handle.Color = Color3.fromRGB(60, 60, 60)

		-- Add barrel
		local barrel = Instance.new("Part")
		barrel.Name = "Barrel"
		barrel.Size = Vector3.new(0.1, 0.1, 0.4)
		barrel.Anchored = true
		barrel.CanCollide = false
		barrel.Color = Color3.fromRGB(50, 50, 50)
		barrel.CFrame = handle.CFrame * CFrame.new(0, -0.4, -0.2)
		barrel.Parent = weapon

		-- Add muzzle attachment
		local muzzle = Instance.new("Attachment")
		muzzle.Name = "MuzzlePoint"
		muzzle.Position = Vector3.new(0, 0, -barrel.Size.Z/2)
		muzzle.Parent = barrel
	elseif slot == "MELEE" then
		handle.Size = Vector3.new(0.2, 0.8, 0.2)
		handle.Color = Color3.fromRGB(80, 80, 80)

		-- Add blade
		local blade = Instance.new("Part")
		blade.Name = "Blade"
		blade.Size = Vector3.new(0.05, 0.8, 0.3)
		blade.Anchored = true
		blade.CanCollide = false
		blade.Color = Color3.fromRGB(200, 200, 200)
		blade.CFrame = handle.CFrame * CFrame.new(0, 0.8, 0)
		blade.Parent = weapon
	elseif slot == "GRENADES" then
		handle.Size = Vector3.new(0.4, 0.4, 0.4)
		handle.Shape = Enum.PartType.Ball
		handle.Color = Color3.fromRGB(50, 80, 50)
	end

	handle.Parent = weapon
	weapon.PrimaryPart = handle

	-- Add standard attachment points
	local attachments = {
		RightGripPoint = CFrame.new(0.1, -0.1, 0),
		LeftGripPoint = CFrame.new(-0.1, -0.1, 0),
		SightPoint = CFrame.new(0, 0.1, 0),
		ShellEjectPoint = CFrame.new(0.1, 0.1, 0)
	}

	for name, offset in pairs(attachments) do
		local attachment = Instance.new("Attachment")
		attachment.Name = name
		attachment.CFrame = offset
		attachment.Parent = handle
	end

	self.currentWeapon = weapon

	-- Parent to viewmodel
	weapon.Parent = self.viewmodelRig

	-- Position at default offset
	local weaponOffset = VIEWMODEL_SETTINGS.WEAPON_OFFSETS[slot] or VIEWMODEL_SETTINGS.WEAPON_OFFSETS.PRIMARY

	if self.container and self.container.PrimaryPart then
		weapon:SetPrimaryPartCFrame(self.container.PrimaryPart.CFrame * weaponOffset)
	end

	return weapon
end

-- Play equip animation
function ViewmodelSystem:playEquipAnimation()
	if not self.currentWeapon or not self.currentWeapon.PrimaryPart then return end

	-- Store original position
	local originalCFrame = self.currentWeapon.PrimaryPart.CFrame

	-- Start position (lower than final)
	local startCFrame = originalCFrame * CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.rad(-10))
	self.currentWeapon:SetPrimaryPartCFrame(startCFrame)

	-- Tween to original position
	local tweenInfo = TweenInfo.new(
		VIEWMODEL_SETTINGS.ANIM.EQUIP_SPEED,
		Enum.EasingStyle.Back,
		Enum.EasingDirection.Out
	)

	-- Create dummy part for tweening
	local dummy = Instance.new("Part")
	dummy.Anchored = true
	dummy.CanCollide = false
	dummy.Transparency = 1
	dummy.CFrame = startCFrame
	dummy.Parent = workspace

	-- Create and play tween
	local tween = TweenService:Create(dummy, tweenInfo, {CFrame = originalCFrame})

	-- Connect update
	local connection = RunService.RenderStepped:Connect(function()
		if self.currentWeapon and self.currentWeapon.PrimaryPart then
			self.currentWeapon:SetPrimaryPartCFrame(dummy.CFrame)
		else
			connection:Disconnect()
		end
	end)

	-- Clean up when done
	tween.Completed:Connect(function()
		connection:Disconnect()
		dummy:Destroy()
	end)

	tween:Play()
end

-- Start the update loop
function ViewmodelSystem:startUpdateLoop()
	-- Clean up existing connection if any
	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end

	-- Start new update connection
	self.updateConnection = RunService.RenderStepped:Connect(function(deltaTime)
		self:update(deltaTime)
	end)

	print("Viewmodel update loop started")
end

-- Get target position based on current state
function ViewmodelSystem:getTargetPosition()
	local offsetType = "DEFAULT"
	if self.isAiming then
		offsetType = "ADS"
	elseif self.isSprinting then
		offsetType = "SPRINT"
	end

	local offset = self.Offsets[offsetType]
	return offset and offset.Position or VIEWMODEL_SETTINGS.DEFAULT_POSITION
end

-- Get target rotation based on current state
function ViewmodelSystem:getTargetRotation()
	local offsetType = "DEFAULT"
	if self.isAiming then
		offsetType = "ADS"
	elseif self.isSprinting then
		offsetType = "SPRINT"
	end

	local offset = self.Offsets[offsetType]
	return offset and offset.Rotation or Vector3.new(0, 0, 0)
end

-- Calculate weapon bob offset
function ViewmodelSystem:getBobOffset()
	local amount = VIEWMODEL_SETTINGS.BOB.AMOUNT

	-- Adjust bob based on state
	if self.isAiming then
		amount = amount * 0.2 -- Reduce when aiming
	elseif self.isSprinting then
		amount = amount * VIEWMODEL_SETTINGS.BOB.SPRINT_MULTIPLIER -- Increase when sprinting
	end

	if not self.isMoving then
		amount = amount * 0.2 -- Reduce when not moving
	end

	return Vector3.new(
		math.sin(self.bobCycle) * amount,
		math.abs(math.cos(self.bobCycle)) * amount,
		0
	)
end

-- Main update function
function ViewmodelSystem:update(deltaTime)
	if not self.container or not self.container.PrimaryPart then return end

	-- Update movement effects
	self:updateSway(deltaTime)
	self:updateBob(deltaTime)
	self:updateRecoil(deltaTime)

	-- Get base position and rotation based on state
	local targetPosition = self:getTargetPosition()
	local targetRotation = self:getTargetRotation()

	-- Convert to CFrames
	local swayRotation = CFrame.Angles(self.currentSway.Y, self.currentSway.X, 0)
	local recoilRotation = CFrame.Angles(self.currentRecoil.X, self.currentRecoil.Y, self.currentRecoil.Z)
	local bobOffset = self:getBobOffset()
	local bobCFrame = CFrame.new(bobOffset.X, bobOffset.Y, 0)

	-- Create position and rotation CFrames
	local positionCFrame = CFrame.new(targetPosition)
	local rotationCFrame = CFrame.Angles(targetRotation.X, targetRotation.Y, targetRotation.Z)

	-- Calculate final CFrame
	local finalCFrame = self.camera.CFrame * 
		positionCFrame * 
		rotationCFrame * 
		swayRotation * 
		recoilRotation * 
		bobCFrame

	-- Update container position
	self.container.PrimaryPart.CFrame = finalCFrame
end

-- Update weapon sway based on mouse movement
function ViewmodelSystem:updateSway(deltaTime)
	local targetX = -self.lastMouseDelta.X * VIEWMODEL_SETTINGS.SWAY.AMOUNT
	local targetY = -self.lastMouseDelta.Y * VIEWMODEL_SETTINGS.SWAY.AMOUNT

	-- Apply less sway when aiming
	if self.isAiming then
		targetX = targetX * 0.5
		targetY = targetY * 0.5
	end

	-- Reset mouse delta after using it
	self.lastMouseDelta = Vector2.new(0, 0)

	-- Smoothly interpolate sway
	self.currentSway = Vector3.new(
		self.currentSway.X + (targetX - self.currentSway.X) * VIEWMODEL_SETTINGS.SWAY.SPEED * deltaTime,
		self.currentSway.Y + (targetY - self.currentSway.Y) * VIEWMODEL_SETTINGS.SWAY.SPEED * deltaTime,
		0
	)
end

-- Update weapon bob cycle
function ViewmodelSystem:updateBob(deltaTime)
	local speed = VIEWMODEL_SETTINGS.BOB.SPEED

	-- Adjust bob speed based on state
	if self.isSprinting then
		speed = speed * VIEWMODEL_SETTINGS.BOB.SPRINT_MULTIPLIER
	elseif not self.isMoving then
		speed = speed * 0.2 -- Slower when not moving
	end

	self.bobCycle = (self.bobCycle + deltaTime * speed) % (2 * math.pi)
end

-- Update recoil recovery
function ViewmodelSystem:updateRecoil(deltaTime)
	-- Gradually return recoil to zero
	local recovery = VIEWMODEL_SETTINGS.RECOIL.RECOVERY_SPEED * deltaTime
	self.currentRecoil = Vector3.new(
		self.currentRecoil.X * (1 - recovery),
		self.currentRecoil.Y * (1 - recovery),
		self.currentRecoil.Z * (1 - recovery)
	)
end

-- Add recoil to viewmodel
function ViewmodelSystem:addRecoil(vertical, horizontal)
	vertical = vertical or 0
	horizontal = horizontal or 0

	-- Apply less recoil while aiming
	if self.isAiming then
		vertical = vertical * 0.6
		horizontal = horizontal * 0.6
	end

	-- Add random rotation
	local rotZ = (math.random() - 0.5) * 0.05

	-- Apply recoil
	self.currentRecoil = Vector3.new(
		self.currentRecoil.X - vertical,
		self.currentRecoil.Y + horizontal,
		self.currentRecoil.Z + rotZ
	)
end

-- Set aiming state
function ViewmodelSystem:setAiming(isAiming)
	if self.isAiming == isAiming then return end
	self.isAiming = isAiming

	-- Don't sprint while aiming
	if isAiming and self.isSprinting then
		self.isSprinting = false
	end

	-- Apply scope positioning override if available
	if self.currentWeapon and isAiming then
		self:applyScopePositioning()
	end
end

-- Apply custom scope positioning if available
function ViewmodelSystem:applyScopePositioning()
	-- This is where you would adjust positioning based on equipped sights
	-- For example, setting a specific ADS position for a red dot sight

	-- Override can be implemented in a future update
end

-- Set sprinting state
function ViewmodelSystem:setSprinting(isSprinting)
	if self.isSprinting == isSprinting then return end

	-- Don't sprint while aiming
	if isSprinting and self.isAiming then return end

	self.isSprinting = isSprinting
end

-- Set movement state
function ViewmodelSystem:setMoving(isMoving)
	self.isMoving = isMoving
end

-- Play a custom animation on the viewmodel
function ViewmodelSystem:playAnimation(animationId, speed)
	if not self.viewmodelRig then return end

	-- Create humanoid if needed for animations
	local humanoid = self.viewmodelRig:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.Parent = self.viewmodelRig
	end

	-- Create animator if needed
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	-- Create and load animation
	local animation = Instance.new("Animation")
	animation.AnimationId = animationId

	local animTrack = animator:LoadAnimation(animation)

	-- Set speed if provided
	if speed then
		animTrack:AdjustSpeed(speed)
	end

	-- Play animation
	animTrack:Play()

	return animTrack
end

-- Attach an accessory to the viewmodel
function ViewmodelSystem:attachAccessory(attachmentModel, attachmentPoint)
	if not self.currentWeapon or not attachmentModel then return nil end

	-- Clone the attachment model
	local attachment = attachmentModel:Clone()

	-- Find attachment point on weapon
	local point = nil

	if typeof(attachmentPoint) == "string" then
		-- Find named attachment point
		point = self.currentWeapon:FindFirstChild(attachmentPoint, true)
	elseif attachmentPoint:IsA("Attachment") then
		-- Use provided attachment
		point = attachmentPoint
	end

	if not point then
		warn("Attachment point not found: " .. tostring(attachmentPoint))
		attachment:Destroy()
		return nil
	end

	-- Position attachment at attachment point
	if attachment:IsA("Model") and attachment.PrimaryPart then
		attachment:SetPrimaryPartCFrame(point.WorldCFrame)
	elseif attachment:IsA("BasePart") then
		attachment.CFrame = point.WorldCFrame
	end

	-- Parent to weapon
	attachment.Parent = self.currentWeapon

	-- Fix properties
	for _, part in ipairs(attachment:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = true
			part.CanCollide = false

			pcall(function()
				part.CollisionGroup = "ViewmodelNoCollision"
			end)
		end
	end

	return attachment
end

-- Clean up viewmodel system
function ViewmodelSystem:cleanup()
	print("Cleaning up ViewmodelSystem...")

	-- Stop the update loop
	if self.updateConnection then
		self.updateConnection:Disconnect()
		self.updateConnection = nil
	end

	-- Stop part added connection
	if self.partAddedConnection then
		self.partAddedConnection:Disconnect()
		self.partAddedConnection = nil
	end

	-- Clean up viewmodel parts
	if self.currentWeapon then
		self.currentWeapon:Destroy()
		self.currentWeapon = nil
	end

	if self.viewmodelRig then
		self.viewmodelRig:Destroy()
		self.viewmodelRig = nil
	end

	-- Don't destroy container so other systems can still use it

	-- Remove from active instances
	local player = Players.LocalPlayer
	if activeInstances[player] == self then
		activeInstances[player] = nil
	end

	-- Remove global reference
	if _G.CurrentViewmodelSystem == self then
		_G.CurrentViewmodelSystem = nil
	end

	print("ViewmodelSystem cleanup complete")
end

-- Handle player leaving
Players.PlayerRemoving:Connect(function(player)
	if activeInstances[player] then
		activeInstances[player]:cleanup()
	end
end)

return ViewmodelSystem