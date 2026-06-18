-- Connected Discord-GitHub | Discord Username: robertcl | Roblox Username: TuPatoDeConfi
--!strict
-- IMPORTANT: The mayority of the functions are written in spanish because I am spanish...
-- The script doesnt do anything on itself because it is the core of all the other scripts in the game, if you join the game you will understand...

local Inventory = {}
Inventory.__index = Inventory

-- SERVICES & SINGLETONS

local DataStoreService = game:GetService("DataStoreService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- DATASTORE CONFIGURATION

-- Using a specific versioned DataStore to guarantee state isolation and prevent migration conflicts.
local InventoryStore = DataStoreService:GetDataStore("Inventario_Final_V15")

-- MODULE DEPENDENCIES & REFERENCES

local MineralTools = ServerStorage:WaitForChild("MineralTools")
local PickaxeData = require(ReplicatedStorage:WaitForChild("PickaxeData"))
local RadarData = require(ReplicatedStorage:WaitForChild("RadarData"))
local OxygenData = require(ReplicatedStorage:WaitForChild("OxygenData"))
local ArtifactData = require(ReplicatedStorage:WaitForChild("ArtifactData")) 
local TankFolder = ReplicatedStorage:WaitForChild("TankCosmetics")

-- INTERNAL SESSION MEMORY (STATE MANAGEMENT)

-- Holds the active session state for all connected users using standard dictionary lookups keyed by UserId strings.
local DatosJugadores = {} 

-- TYPE DEFINITIONS (LUAU COMPILER OPTIMIZATION)

type ItemData = { Nombre: string, Peso: number? }
type PlayerProfile = {
	Inventario: { [number]: ItemData },
	Propiedades: { [string]: boolean },
	Coleccion: { [string]: boolean },
	Portales: { Desierto: boolean, Hielo: boolean },
	QuestStep: number,
	OwnsStarterPack: boolean,
	StartTime: number
}

-- HELPER / UTILITY FUNCTIONS

--[[
	@private esMineralApilable
	Evaluates if an item is a stackable resource (ore/mineral) by cross-referencing global item configuration modules.
	Returns true if the item does not belong to functional tool/gear datasets.
--]]
local function esMineralApilable(nombre: string): boolean
	return not PickaxeData.Picos[nombre] and not RadarData.Radares[nombre] and not OxygenData.Tanks[nombre]
end

--[[
	@private asegurarCarpetaPropiedades
	Ensures the physical replication container exists under the Player instance. 
	This allows the client UI to read unlocked/owned blueprints via ValueObject listening.
--]]
local function asegurarCarpetaPropiedades(player: Player): Folder
	local folder = player:FindFirstChild("OwnedPickaxes")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "OwnedPickaxes"
		folder.Parent = player
	end
	return folder :: Folder
end

--[[
	@private asegurarValoresPortales
	Mutates or initializes internal state primitive values representing progressive world unlocks (Portals).
	Binds data mutators to .Changed events to mirror property changes dynamically to the central memory matrix.
--]]
local function asegurarValoresPortales(player: Player, datosPortales: { Desierto: boolean, Hielo: boolean })
	local userId = tostring(player.UserId)
	
	local portalDesierto = player:FindFirstChild("PortalDesierto") or Instance.new("BoolValue")
	portalDesierto.Name = "PortalDesierto"
	portalDesierto.Value = datosPortales.Desierto or false
	portalDesierto.Parent = player

	portalDesierto.Changed:Connect(function(newVal: boolean)
		if DatosJugadores[userId] then 
			DatosJugadores[userId].Portales.Desierto = newVal 
		end
	end)

	local portalHielo = player:FindFirstChild("PortalHielo") or Instance.new("BoolValue")
	portalHielo.Name = "PortalHielo"
	portalHielo.Value = datosPortales.Hielo or false
	portalHielo.Parent = player

	portalHielo.Changed:Connect(function(newVal: boolean)
		if DatosJugadores[userId] then 
			DatosJugadores[userId].Portales.Hielo = newVal 
		end
	end)
end

--[[
	@private aplicarTanqueVisual
	Handles the procedurally aligned CFrame welding mechanics for character-based cosmetics (Oxygen Tanks).
	Implements collision-filtering and structural optimization (Massless) to prevent physics anomalies on the character controller.
--]]
local function aplicarTanqueVisual(player: Player, nombreTanque: string)
	local char = player.Character
	if not char then return end

	local data = OxygenData.Tanks[nombreTanque]
	if not data or not TankFolder:FindFirstChild(data.ModelName) then return end

	local viejo = char:FindFirstChild("BackTank")
	if viejo then viejo:Destroy() end

	local clon = TankFolder[data.ModelName]:Clone()
	clon.Name = "BackTank"

	local handle = clon:IsA("BasePart") and clon or clon.PrimaryPart or clon:FindFirstChildWhichIsA("BasePart")
	if not handle then 
		clon:Destroy() 
		return 
	end

	clon.Parent = char
	local cuerpo = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")

	if cuerpo and handle then
		local weld = Instance.new("Weld")
		weld.Name = "TankWeld"
		weld.Part0 = cuerpo
		weld.Part1 = handle
		-- CFrame transformation matrix offsets the object safely behind the character's relative posterior axis
		weld.C0 = CFrame.new(0, 0, 0.7) * CFrame.Angles(0, math.rad(90), math.rad(180))
		weld.Parent = handle
	end

	for _, p in pairs(clon:GetDescendants()) do
		if p:IsA("BasePart") then 
			p.CanCollide = false
			p.Massless = true 
		end
	end
end

-- CORE INVENTORY CORE INTERFACES

--[[
	@interface Inventory.load
	Synchronously invokes DataStore threads wrapped inside protected execution calls (pcall) to safe-guard against server outages.
	Performs linear cleanups, populates structural defaults for first-time sessions, and handles automatic stack-merging algorithms.
--]]
function Inventory.load(player: Player)
	local userId = tostring(player.UserId)
	local folder = asegurarCarpetaPropiedades(player)

	local datosCargados = nil
	local success, err = pcall(function()
		datosCargados = InventoryStore:GetAsync(userId)
	end)

	if not success then
		warn("Critical error fetching profile data for structural entry " .. userId .. ": " .. tostring(err))
	end

	if datosCargados then
		DatosJugadores[userId] = datosCargados

		-- Backwards-compatibility schema patch for legacy database structural definitions
		if not DatosJugadores[userId].Portales then
			DatosJugadores[userId].Portales = {
				Desierto = DatosJugadores[userId].PortalAbierto or false,
				Hielo = false
			}
			DatosJugadores[userId].PortalAbierto = nil 
		end

		if DatosJugadores[userId].Portales.Hielo == nil then DatosJugadores[userId].Portales.Hielo = false end
		if DatosJugadores[userId].QuestStep == nil then DatosJugadores[userId].QuestStep = 0 end
		if DatosJugadores[userId].Coleccion == nil then DatosJugadores[userId].Coleccion = {} end

		local inventarioLimpio = {}
		local pesosAcumulados = {}

		-- Algorithmic data compression: Aggregates weights of duplicates into single hashmap indexes
		for _, item in pairs(DatosJugadores[userId].Inventario) do
			if esMineralApilable(item.Nombre) then
				pesosAcumulados[item.Nombre] = (pesosAcumulados[item.Nombre] or 0) + (item.Peso or 1)
			else
				table.insert(inventarioLimpio, item)
			end
		end

		for nombreMat, pesoTotal in pairs(pesosAcumulados) do
			table.insert(inventarioLimpio, {Nombre = nombreMat, Peso = pesoTotal})
		end
		
		DatosJugadores[userId].Inventario = inventarioLimpio
		
		if DatosJugadores[userId].OwnsStarterPack then
			player:SetAttribute("OwnsStarterPack", true)
		end
		if not DatosJugadores[userId].StartTime then
			DatosJugadores[userId].StartTime = os.time()
		end

		player:SetAttribute("StartTime", DatosJugadores[userId].StartTime)
	else
		-- Profile initialization factory providing architectural defaults for fresh player accounts
		DatosJugadores[userId] = {
			Inventario = {
				{Nombre = "Wooden Pickaxe", Peso = nil},
				{Nombre = "Basic Radar", Peso = nil},
				{Nombre = "Basic Tank", Peso = nil}
			},
			Propiedades = {["Wooden Pickaxe"] = true, ["Basic Radar"] = true, ["Basic Tank"] = true},
			Coleccion = {},
			Portales = { Desierto = false, Hielo = false },
			QuestStep = 0,
			OwnsStarterPack = false,
			StartTime = os.time() 
		}
	end

	-- Structural synchronization between memory cache values and instance-level network elements
	asegurarValoresPortales(player, DatosJugadores[userId].Portales)
	for nombre, _ in pairs(DatosJugadores[userId].Propiedades) do
		if not folder:FindFirstChild(nombre) then
			Instance.new("BoolValue", folder).Name = nombre
		end
	end

	local backpack = player:WaitForChild("Backpack")
	local starterGear = player:WaitForChild("StarterGear") 

	for _, item in pairs(DatosJugadores[userId].Inventario) do
		local toolBase = MineralTools:FindFirstChild(item.Nombre)
		if toolBase then
			local clon = toolBase:Clone()
			if item.Peso then
				local v = Instance.new("NumberValue")
				v.Name = "Weight"
				v.Value = item.Peso
				v.Parent = clon
			end
			clon.Parent = backpack

			if PickaxeData.Picos[item.Nombre] or RadarData.Radares[item.Nombre] or OxygenData.Tanks[item.Nombre] then
				toolBase:Clone().Parent = starterGear
			end
		end
	end

	local nombreTanque = Inventory.GetEquippedTankName(player)
	local dataT = OxygenData.Tanks[nombreTanque]
	player:SetAttribute("EquippedTank", nombreTanque)
	player:SetAttribute("MaxOxygen", dataT.MaxOxygen)
	player:SetAttribute("Oxygen", dataT.MaxOxygen)

	-- Thread scheduler deferral to wait out character instantiation sequences safely before assigning models
	task.delay(1, function()
		if player.Character then
			aplicarTanqueVisual(player, nombreTanque)
			local picoActual = Inventory.GetEquippedPickaxeName(player)
			local ev = ServerStorage:FindFirstChild("ActualizarCosmeticoEvento")
			if ev then ev:Fire(player, picoActual) end
		end
	end)

	player:SetAttribute("InventarioCargado", true)
end

--[[
	@interface Inventory.save
	Pushes current session state maps into Cloud Data Stores. Wrapped inside an explicit pcall
	to gracefully mitigate operational network throttling boundaries or active rate limits.
--]]
function Inventory.save(player: Player)
	local userId = tostring(player.UserId)
	if DatosJugadores[userId] then
		DatosJugadores[userId].OwnsStarterPack = player:GetAttribute("OwnsStarterPack") or false
		DatosJugadores[userId].StartTime = player:GetAttribute("StartTime")

		local success, err = pcall(function() 
			InventoryStore:SetAsync(userId, DatosJugadores[userId]) 
		end)
		if not success then
			warn("Failed state preservation sequence for User " .. userId .. ": " .. tostring(err))
		end
	end
end

-- EQUIPMENT UPGRADE INTERFACES

--[[
	@interface Inventory.UpdatePickaxe
	Handles the asset swapping and backend inventory state mutations when purchasing or equipping higher tier Pickaxes.
	Purges prior physical tool references dynamically out of the player backpack stack.
--]]
function Inventory.UpdatePickaxe(player: Player, nuevoPicoNombre: string)
	local userId = tostring(player.UserId)
	local data = DatosJugadores[userId]
	if not data then return end

	data.Propiedades[nuevoPicoNombre] = true
	local f = asegurarCarpetaPropiedades(player)
	if not f:FindFirstChild(nuevoPicoNombre) then 
		Instance.new("BoolValue", f).Name = nuevoPicoNombre 
	end

	for i = #data.Inventario, 1, -1 do
		if PickaxeData.Picos[data.Inventario[i].Nombre] then 
			table.remove(data.Inventario, i) 
		end
	end
	table.insert(data.Inventario, {Nombre = nuevoPicoNombre, Peso = nil})

	local bp = player:FindFirstChild("Backpack")
	local sg = player:FindFirstChild("StarterGear") 
	local char = player.Character
	if char then char.Humanoid:UnequipTools() end

	local function limpiar(c: Instance?)
		if not c then return end
		for _, t in pairs(c:GetChildren()) do
			if t:IsA("Tool") and PickaxeData.Picos[t.Name] then 
				t:Destroy() 
			end
		end
	end
	limpiar(bp); limpiar(char); limpiar(sg)

	local tool = MineralTools:FindFirstChild(nuevoPicoNombre)
	if tool then 
		tool:Clone().Parent = bp 
		if sg then tool:Clone().Parent = sg end
	end

	local ev = ServerStorage:FindFirstChild("ActualizarCosmeticoEvento")
	if ev then ev:Fire(player, nuevoPicoNombre) end
end

--[[
	@interface Inventory.UpdateRadar
	Upgrades radar tools by wiping previous entries and appending the item into structural data tables.
--]]
function Inventory.UpdateRadar(player: Player, nuevoRadarNombre: string)
	local userId = tostring(player.UserId)
	local data = DatosJugadores[userId]
	if not data then return end
	
	data.Propiedades[nuevoRadarNombre] = true
	local f = asegurarCarpetaPropiedades(player)
	if not f:FindFirstChild(nuevoRadarNombre) then 
		Instance.new("BoolValue", f).Name = nuevoRadarNombre 
	end

	for i = #data.Inventario, 1, -1 do
		if RadarData.Radares[data.Inventario[i].Nombre] then 
			table.remove(data.Inventario, i) 
		end
	end
	table.insert(data.Inventario, {Nombre = nuevoRadarNombre, Peso = nil})

	local bp = player:FindFirstChild("Backpack")
	local char = player.Character
	if char then char.Humanoid:UnequipTools() end

	local function limpiar(c: Instance?)
		if not c then return end
		for _, t in pairs(c:GetChildren()) do
			if t:IsA("Tool") and RadarData.Radares[t.Name] then 
				t:Destroy() 
			end
		end
	end
	limpiar(bp); limpiar(char)

	local tool = MineralTools:FindFirstChild(nuevoRadarNombre)
	if tool then tool:Clone().Parent = bp end
end

--[[
	@interface Inventory.UpdateTank
	Reconfigures internal attribute parameters for character-based localized resources (MaxOxygen) and binds visual assets.
--]]
function Inventory.UpdateTank(player: Player, nuevoTanqueNombre: string)
	local userId = tostring(player.UserId)
	local data = DatosJugadores[userId]
	if not data then return end

	data.Propiedades[nuevoTanqueNombre] = true
	for i = #data.Inventario, 1, -1 do
		if OxygenData.Tanks[data.Inventario[i].Nombre] then 
			table.remove(data.Inventario, i) 
		end
	end
	table.insert(data.Inventario, {Nombre = nuevoTanqueNombre, Peso = nil})

	local tankData = OxygenData.Tanks[nuevoTanqueNombre]
	player:SetAttribute("EquippedTank", nuevoTanqueNombre)
	player:SetAttribute("MaxOxygen", tankData.MaxOxygen)
	player:SetAttribute("Oxygen", tankData.MaxOxygen)

	aplicarTanqueVisual(player, nuevoTanqueNombre)
end

-- RESOURCE DISPATCH AND ITEM DESTRUCTION

--[[
	@interface Inventory.AddItem
	Central ingest point for newly mined materials and special game loop rewards.
	Performs conditional branching to separate non-stackable entries from multi-weight configurations.
--]]
function Inventory.AddItem(player: Player, toolName: string, peso: number?)
	local userId = tostring(player.UserId)
	if not DatosJugadores[userId] then return end

	local pesoAAgregar = peso or 1
	DatosJugadores[userId].Coleccion[toolName] = true

	if esMineralApilable(toolName) then
		local encontradoLogico = false
		for _, item in pairs(DatosJugadores[userId].Inventario) do
			if item.Nombre == toolName then
				item.Peso = (item.Peso or 0) + pesoAAgregar
				encontradoLogico = true
				break
			end
		end

		if not encontradoLogico then
			table.insert(DatosJugadores[userId].Inventario, {Nombre = toolName, Peso = pesoAAgregar})
		end

		local char = player.Character
		local backpack = player:FindFirstChild("Backpack")
		local toolFisica = (char and char:FindFirstChild(toolName)) or (backpack and backpack:FindFirstChild(toolName))

		if toolFisica then
			local weightVal = toolFisica:FindFirstChild("Weight") or Instance.new("NumberValue")
			weightVal.Name = "Weight"
			weightVal.Parent = toolFisica
			weightVal.Value = weightVal.Value + pesoAAgregar
		else
			local toolBase = MineralTools:FindFirstChild(toolName)
			if toolBase and backpack then
				local clon = toolBase:Clone()
				local v = Instance.new("NumberValue")
				v.Name = "Weight"
				v.Value = pesoAAgregar
				v.Parent = clon
				clon.Parent = backpack
			end
		end
	else
		table.insert(DatosJugadores[userId].Inventario, {Nombre = toolName, Peso = nil})
		local toolBase = MineralTools:FindFirstChild(toolName)
		if toolBase then
			local clon = toolBase:Clone()
			clon.Parent = player:WaitForChild("Backpack")
		end
	end
end

--[[
	@interface Inventory.AddArtifact
	Unique execution registry for discovering rare collector items. 
	Guarantees atomic uniqueness via targeted boolean tracking hash maps.
--]]
function Inventory.AddArtifact(player: Player, id: string): boolean
	local userId = tostring(player.UserId)
	local data = DatosJugadores[userId]
	if not data then return false end
	if not data.Coleccion[id] then
		data.Coleccion[id] = true
		return true
	end
	return false
end

--[[
	@interface Inventory.ClearMinerals
	Wipes pure volatile elements (minerals/ores) out of the memory table during sell mechanics while retaining foundational user progression.
--]]
function Inventory.ClearMinerals(player: Player)
	local userId = tostring(player.UserId)
	local data = DatosJugadores[userId]
	if not data then return end
	local nueva = {}
	for _, item in pairs(data.Inventario) do
		if PickaxeData.Picos[item.Nombre] or RadarData.Radares[item.Nombre] or OxygenData.Tanks[item.Nombre] then
			table.insert(nueva, item)
		end
	end
	data.Inventario = nueva
end

--[[
	@interface Inventory.RemoveSpecificItem
	Subtracts incremental weight parameters or fully untracks functional tools out of data schemas.
	Implements cleanup behaviors targeting instances inside replication states.
--]]
function Inventory.RemoveSpecificItem(player: Player, nombreTool: string, objetoExacto: Instance?, cantidadRestar: number?)
	local userId = tostring(player.UserId)
	local data = DatosJugadores[userId]
	if not data then return end

	if esMineralApilable(nombreTool) and cantidadRestar then
		for i, item in pairs(data.Inventario) do
			if item.Nombre == nombreTool then
				item.Peso = (item.Peso or 0) - cantidadRestar
				if item.Peso <= 0 then
					table.remove(data.Inventario, i)
				end
				break
			end
		end

		local char = player.Character
		local backpack = player:FindFirstChild("Backpack")
		local toolFisica = (char and char:FindFirstChild(nombreTool)) or (backpack and backpack:FindFirstChild(nombreTool))

		if toolFisica then
			local v = toolFisica:FindFirstChild("Weight")
			if v then
				v.Value = v.Value - cantidadRestar
				if v.Value <= 0 then toolFisica:Destroy() end
			end
		end
		return
	end

	for i = #data.Inventario, 1, -1 do
		if data.Inventario[i].Nombre == nombreTool then
			table.remove(data.Inventario, i)
			break 
		end
	end

	if objetoExacto and objetoExacto:IsDescendantOf(game) then
		objetoExacto:Destroy()
	else
		local backpack = player:FindFirstChild("Backpack")
		local char = player.Character
		local function buscarYBorrar(contenedor: Instance?): boolean
			if not contenedor then return false end
			local item = contenedor:FindFirstChild(nombreTool)
			if item and item:IsA("Tool") then
				item:Destroy()
				return true
			end
			return false
		end
		local borrado = buscarYBorrar(backpack)
		if not borrado then buscarYBorrar(char) end
	end
end

-- STATE REFLECTION (GETTER SYSTEM)

function Inventory.GetEquippedPickaxeName(player: Player): string
	local d = DatosJugadores[tostring(player.UserId)]
	if d then
		for _, item in pairs(d.Inventario) do
			if PickaxeData.Picos[item.Nombre] then return item.Nombre end
		end
	end
	return "Wooden Pickaxe"
end

function Inventory.GetEquippedTankName(player: Player): string
	local d = DatosJugadores[tostring(player.UserId)]
	if d then
		for _, item in pairs(d.Inventario) do
			if OxygenData.Tanks[item.Nombre] then return item.Nombre end
		end
	end
	return "Basic Tank"
end

function Inventory.GetCollection(player: Player): { [string]: boolean }
	local d = DatosJugadores[tostring(player.UserId)]
	return d and d.Coleccion or {}
end

function Inventory.HasItem(player: Player, nombre: string): boolean
	local d = DatosJugadores[tostring(player.UserId)]
	return d and d.Propiedades[nombre] == true or false
end

function Inventory.GetQuestStep(player: Player): number
	local d = DatosJugadores[tostring(player.UserId)]
	return d and d.QuestStep or 0
end

-- PROGRESSION STATE MUTATORS

function Inventory.UpdateQuestStep(player: Player, paso: number)
	local userId = tostring(player.UserId)
	if DatosJugadores[userId] then
		DatosJugadores[userId].QuestStep = paso
	end
end

function Inventory.UnlockItem(player: Player, nombreItem: string)
	local userId = tostring(player.UserId)
	local data = DatosJugadores[userId]
	if not data then return end

	data.Propiedades[nombreItem] = true
	local f = asegurarCarpetaPropiedades(player)
	if not f:FindFirstChild(nombreItem) then 
		Instance.new("BoolValue", f).Name = nombreItem 
	end
end

-- LIFECYCLE MEMORY MANAGEMENT BOUNDARIES

-- Prevents memory leakage by clearing session data vectors immediately upon connection termination.
Players.PlayerRemoving:Connect(function(player: Player)
	Inventory.save(player)
	DatosJugadores[tostring(player.UserId)] = nil
end)

return Inventory
