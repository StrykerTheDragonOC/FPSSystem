-- RaycastHitboxV4.lua
-- Modern raycast hitbox system with enhanced precision and visualization
-- Place in ReplicatedStorage

local RaycastHitboxV4 = {}
RaycastHitboxV4.__index = RaycastHitboxV4

-- Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local PhysicsService = game:GetService("PhysicsService")
local Debris = game:GetService("Debris")

-- Constants
local MAX_HITBOX_SIZE = 20 -- Maximum supported size for a hitbox part
local UPDATE_RATE = 1/60 -- How often the hitbox updates (60hz)
local VISUALIZATION_LIFETIME = 1/30 -- How long visualization parts stay (30hz)

-- Enumeration for detection mode
RaycastHitboxV4.DetectionMode = {
	Standard = 1, -- Checks at corners only
	Precise = 2,  -- Uses more sample points for better detection
	Adaptive = 3  -- Automatically chooses points based on size and velocity
}

-- Module signal class
local Signal = {}
Signal.__index = Signal

function Signal.new()
	local self = setmetatable({}, Signal)
	self._connections = {}
	self._connectIndex = 0
	return self
end

function Signal:Connect(func)
	self._connectIndex = self._connectIndex + 1
	local connection = {
		Func = func,
		Index = self._connectIndex,
		Connected = true,
		Disconnect = function(conn)
			conn.Connected = false
			self._connections[conn.Index] = nil
		end
	}

	self._connections[self._connectIndex] = connection
	return connection
end

function Signal:Fire(...)
	for _, connection in pairs(self._connections) do
		task.spawn(connection.Func, ...)
	end
end

function Signal:Destroy()
	for _, connection in pairs(self._connections) do
		connection:Disconnect()
	end
	self._connections = {}
end

-- Create a new raycast hitbox
function RaycastHitboxV4.new(attachment)
	local self = setmetatable({}, RaycastHitboxV4)

	-- Initialize base properties
	self.Attachment = attachment
	self.Hitboxes = {}
	self.RaycastParams = RaycastParams.new()
	self.RaycastParams.FilterType = Enum.RaycastFilterType.Exclude
	self.RaycastParams.IgnoreWater = true
	self.RaycastParams.CollisionGroup = "Default"

	-- Set filter based on attachment
	if attachment then
		self:SetFilterFromAttachment(attachment)
	end

	-- Hit detection settings
	self.DetectionMode = RaycastHitboxV4.DetectionMode.Standard
	self.SamplesPerCuboid = 8  -- Default corners only
	self.HitRate = UPDATE_RATE -- Default 60hz
	self.HitDebounce = {}      -- Track hit debounce per instance
	self.DebounceTime = 0.1    -- Default debounce time

	-- Visual settings
	self.Visualizer = false
	self.VisualizerColor = Color3.fromRGB(255, 0, 0)
	self.VisualizerTransparency = 0.5
	self.VisualizerLifetime = VISUALIZATION_LIFETIME

	-- Initialize signal
	self.OnHit = Signal.new()

	-- Handle automatic cleanup if Attachment is a Model that gets removed
	if attachment and attachment:IsA("Model") then
		attachment.AncestryChanged:Connect(function(_, parent)
			if not parent then
				self:Destroy()
			end
		end)
	end

	return self
end

-- Set filter from attachment
function RaycastHitboxV4:SetFilterFromAttachment(attachment)
	local filterInstances = {}

	-- If attachment is a character, add player
	if attachment:IsA("Model") and attachment:FindFirstChildOfClass("Humanoid") then
		table.insert(filterInstances, attachment)

		-- Try to find player for this character
		for _, player in pairs(Players:GetPlayers()) do
			if player.Character == attachment then
				-- If in a team, exclude teammates (for team-based games)
				if player.Team then
					for _, otherPlayer in pairs(Players:GetPlayers()) do
						if otherPlayer.Team == player.Team then
							table.insert(filterInstances, otherPlayer.Character)
						end
					end
				end
				break
			end
		end
	elseif attachment:IsA("BasePart") then
		-- If it's a part, add its ancestors
		local model = attachment:FindFirstAncestorOfClass("Model")
		if model then
			table.insert(filterInstances, model)
		else
			table.insert(filterInstances, attachment)
		end
	end

	-- Set filter
	self.RaycastParams.FilterDescendantsInstances = filterInstances
end

-- Add a hitbox part to track
function RaycastHitboxV4:AddHitbox(part, priority)
	if not part or not part:IsA("BasePart") then
		warn("RaycastHitboxV4: AddHitbox requires a BasePart")
		return
	end

	-- Check part size
	if part.Size.Magnitude > MAX_HITBOX_SIZE then
		warn("RaycastHitboxV4: Part size exceeds maximum supported hitbox size:", part:GetFullName())
	end

	-- Create hitbox entry
	local hitbox = {
		Part = part,
		Priority = priority or 1,
		LastPosition = part.Position,
		LastUpdate = tick(),
		SamplePoints = {},
		DebounceHits = {}
	}

	-- Store the hitbox
	table.insert(self.Hitboxes, hitbox)

	-- Attach to part events
	local ancestryChangedConn
	ancestryChangedConn = part.AncestryChanged:Connect(function(_, parent)
		if not parent then
			-- Part was removed, remove from hitboxes
			for i, hb in ipairs(self.Hitboxes) do
				if hb.Part == part then
					table.remove(self.Hitboxes, i)
					ancestryChangedConn:Disconnect()
					break
				end
			end
		end
	end)

	-- Create visualization part if enabled
	if self.Visualizer then
		self:VisualizeHitbox(hitbox)
	end

	-- Update sample points
	self:UpdateSamplePoints(hitbox)

	return hitbox
end

-- Remove a hitbox
function RaycastHitboxV4:RemoveHitbox(part)
	for i, hitbox in ipairs(self.Hitboxes) do
		if hitbox.Part == part then
			table.remove(self.Hitboxes, i)
			return true
		end
	end
	return false
end

-- Update sample points for a hitbox based on detection mode
function RaycastHitboxV4:UpdateSamplePoints(hitbox)
	local part = hitbox.Part
	local size = part.Size
	local mode = self.DetectionMode

	-- Clear existing sample points
	hitbox.SamplePoints = {}

	-- Generate points based on detection mode
	if mode == RaycastHitboxV4.DetectionMode.Standard then
		-- Just use the 8 corners of the box
		self:GenerateCornerSamples(hitbox)
	elseif mode == RaycastHitboxV4.DetectionMode.Precise then
		-- Use corners plus additional points inside
		self:GenerateCornerSamples(hitbox)
		self:GenerateInnerSamples(hitbox, 3) -- Add 27 inner points (3x3x3 grid)
	elseif mode == RaycastHitboxV4.DetectionMode.Adaptive then
		-- Adapt points based on size and movement
		local sizeScale = math.ceil(part.Size.Magnitude / 4)
		local innerPoints = math.min(5, math.max(2, sizeScale))

		self:GenerateCornerSamples(hitbox)
		self:GenerateInnerSamples(hitbox, innerPoints)
	end
end

-- Generate corner sample points
function RaycastHitboxV4:GenerateCornerSamples(hitbox)
	local part = hitbox.Part
	local size = part.Size / 2

	-- Generate all 8 corners
	for x = -1, 1, 2 do
		for y = -1, 1, 2 do
			for z = -1, 1, 2 do
				local offset = Vector3.new(size.X * x, size.Y * y, size.Z * z)
				table.insert(hitbox.SamplePoints, offset)
			end
		end
	end
end

-- Generate inner sample points for more precise detection
function RaycastHitboxV4:GenerateInnerSamples(hitbox, divisions)
	local part = hitbox.Part
	local size = part.Size / 2

	-- Generate interior grid points
	for x = -1, 1, 2/divisions do
		for y = -1, 1, 2/divisions do
			for z = -1, 1, 2/divisions do
				-- Skip if this is a corner (already added)
				if math.abs(x) ~= 1 or math.abs(y) ~= 1 or math.abs(z) ~= 1 then
					local offset = Vector3.new(size.X * x, size.Y * y, size.Z * z)
					table.insert(hitbox.SamplePoints, offset)
				end
			end
		end
	end
end

-- Start hitbox detection
function RaycastHitboxV4:HitStart()
	if self.HitConnection then
		self:HitStop() -- Stop existing connection
	end

	self.Active = true

	-- Create update connection
	self.HitConnection = RunService.Heartbeat:Connect(function(dt)
		if not self.Active then return end

		-- Update hitboxes
		self:UpdateHitboxes(dt)
	end)

	return self
end

-- Stop hitbox detection
function RaycastHitboxV4:HitStop()
	self.Active = false

	if self.HitConnection then
		self.HitConnection:Disconnect()
		self.HitConnection = nil
	end

	return self
end

-- Update all hitboxes
function RaycastHitboxV4:UpdateHitboxes(dt)
	-- Process each hitbox
	for _, hitbox in ipairs(self.Hitboxes) do
		-- Check if part exists and is valid
		if not hitbox.Part or not hitbox.Part.Parent then
			continue
		end

		-- Get current part CFrame
		local currentCFrame = hitbox.Part.CFrame
		local currentPosition = hitbox.Part.Position

		-- Check if part has moved enough to need update
		local positionDelta = (currentPosition - hitbox.LastPosition).Magnitude
		local timeDelta = tick() - hitbox.LastUpdate

		-- Skip if not moved significantly and not enough time passed
		if positionDelta < 0.01 and timeDelta < self.HitRate then
			continue
		end

		-- Update last position
		hitbox.LastPosition = currentPosition
		hitbox.LastUpdate = tick()

		-- Cast rays for all sample points
		self:ProcessHitboxPoints(hitbox, currentCFrame)
	end
end

-- Process all points in a hitbox
function RaycastHitboxV4:ProcessHitboxPoints(hitbox, currentCFrame)
	-- Calculate ray length based on movement
	local part = hitbox.Part
	local velocity = part.Velocity
	local speedMagnitude = velocity.Magnitude

	-- Use velocity as ray length with minimum of part size
	local rayLength = math.max(part.Size.Magnitude, speedMagnitude * self.HitRate)

	-- Draw visualization if enabled
	if self.Visualizer then
		self:VisualizeHitbox(hitbox)
	end

	-- Process each sample point
	for _, offset in ipairs(hitbox.SamplePoints) do
		-- Transform offset to world space
		local pointPosition = currentCFrame:PointToWorldSpace(offset)
		local rayDirection = velocity.Unit * rayLength

		-- Use zero vector if velocity is too small
		if speedMagnitude < 0.1 then
			rayDirection = Vector3.new(0, -rayLength, 0) -- Default downward if not moving
		end

		-- Cast ray
		local result = workspace:Raycast(pointPosition, rayDirection, self.RaycastParams)

		-- Process hit result
		if result then
			self:ProcessHitResult(hitbox, result)
		end
	end
end

-- Process a hit result
function RaycastHitboxV4:ProcessHitResult(hitbox, result)
	local hitPart = result.Instance
	local hitPosition = result.Position
	local hitNormal = result.Normal

	-- Skip if debounce active for this instance
	if self.HitDebounce[hitPart] then
		return
	end

	-- Find humanoid in hit target
	local humanoid = self:FindHumanoidFromHit(hitPart)

	-- Fire hit event
	self.OnHit:Fire(hitPart, humanoid, hitPosition, hitNormal)

	-- Set debounce for this instance
	self.HitDebounce[hitPart] = true

	-- Clear debounce after time
	task.delay(self.DebounceTime, function()
		self.HitDebounce[hitPart] = nil
	end)

	-- Draw hit visualization if enabled
	if self.Visualizer then
		self:VisualizeHit(hitPosition, hitNormal)
	end
end

-- Find humanoid from hit part
function RaycastHitboxV4:FindHumanoidFromHit(hitPart)
	-- First check in parent
	local parent = hitPart.Parent
	if parent then
		local humanoid = parent:FindFirstChildOfClass("Humanoid")
		if humanoid then
			return humanoid
		end

		-- Then check in grandparent
		local grandparent = parent.Parent
		if grandparent then
			humanoid = grandparent:FindFirstChildOfClass("Humanoid")
			if humanoid then
				return humanoid
			end
		end
	end

	return nil
end

-- Create visualization of a hitbox
function RaycastHitboxV4:VisualizeHitbox(hitbox)
	if not self.Visualizer then return end

	local part = hitbox.Part

	-- Create visualization part that matches hitbox size
	local visual = Instance.new("Part")
	visual.Size = part.Size
	visual.CFrame = part.CFrame
	visual.Anchored = true
	visual.CanCollide = false
	visual.Material = Enum.Material.SmoothPlastic
	visual.Color = self.VisualizerColor
	visual.Transparency = self.VisualizerTransparency
	visual.Name = "HitboxVisual"

	-- Make non-interactive
	visual.CastShadow = false

	-- Add to workspace
	visual.Parent = workspace

	-- Clean up after a short time
	Debris:AddItem(visual, self.VisualizerLifetime)

	-- Draw rays for sample points if detailed visualization is enabled
	if self.Visualizer == "Detailed" then
		for _, offset in ipairs(hitbox.SamplePoints) do
			-- Draw a small sphere at each sample point
			local pointVisual = Instance.new("Part")
			pointVisual.Shape = Enum.PartType.Ball
			pointVisual.Size = Vector3.new(0.1, 0.1, 0.1)
			pointVisual.Position = part.CFrame:PointToWorldSpace(offset)
			pointVisual.Anchored = true
			pointVisual.CanCollide = false
			pointVisual.Material = Enum.Material.Neon
			pointVisual.Color = Color3.fromRGB(255, 255, 0)
			pointVisual.Transparency = 0.3
			pointVisual.Name = "SamplePoint"

			-- Add to workspace
			pointVisual.Parent = workspace

			-- Clean up after a short time
			Debris:AddItem(pointVisual, self.VisualizerLifetime)
		end
	end
end

-- Visualize a hit point
function RaycastHitboxV4:VisualizeHit(position, normal)
	if not self.Visualizer then return end

	-- Create a sphere at hit position
	local hitMarker = Instance.new("Part")
	hitMarker.Shape = Enum.PartType.Ball
	hitMarker.Size = Vector3.new(0.3, 0.3, 0.3)
	hitMarker.Position = position
	hitMarker.Anchored = true
	hitMarker.CanCollide = false
	hitMarker.Material = Enum.Material.Neon
	hitMarker.Color = Color3.fromRGB(255, 0, 0)
	hitMarker.Transparency = 0.3
	hitMarker.Name = "HitPoint"

	-- Make non-interactive
	hitMarker.CastShadow = false

	-- Add to workspace
	hitMarker.Parent = workspace

	-- Clean up after a short time
	Debris:AddItem(hitMarker, self.VisualizerLifetime * 2)

	-- Draw normal vector if detailed visualization enabled
	if self.Visualizer == "Detailed" then
		local normalLine = Instance.new("Part")
		normalLine.Size = Vector3.new(0.05, 0.05, 1)
		normalLine.CFrame = CFrame.lookAt(position, position + normal)
			* CFrame.new(0, 0, -0.5) -- Center the line
		normalLine.Anchored = true
		normalLine.CanCollide = false
		normalLine.Material = Enum.Material.Neon
		normalLine.Color = Color3.fromRGB(0, 255, 0)
		normalLine.Transparency = 0.3
		normalLine.Name = "HitNormal"

		-- Add to workspace
		normalLine.Parent = workspace

		-- Clean up after a short time
		Debris:AddItem(normalLine, self.VisualizerLifetime * 2)
	end
end

-- Helper function to highlight hitboxes without performing actual hit detection
function RaycastHitboxV4:HighlightHitboxes()
	if not self.Visualizer then return end

	for _, hitbox in ipairs(self.Hitboxes) do
		if not hitbox.Part or not hitbox.Part.Parent then
			continue
		end

		-- Only visualize occasionally to avoid too many parts
		if math.random() < 0.1 then
			self:VisualizeHitbox(hitbox)
		end
	end
end

-- Clean up everything
function RaycastHitboxV4:Destroy()
	self:HitStop()

	-- Clear signals
	self.OnHit:Destroy()

	-- Clear hitboxes
	self.Hitboxes = {}
	self.HitDebounce = {}

	return nil
end

return RaycastHitboxV4