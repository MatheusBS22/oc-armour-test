-- drone.lua
-- Roda direto na EEPROM do drone — sem require(), sem OpenOS
-- Usa apenas APIs nativas: component, computer
-- 2 Linked Cards: menor canal = tablet, maior = server

local function proxy(name)
    local addr = component.list(name)()
    if not addr then return nil end
    return component.proxy(addr)
end

-- Serialização simples sem require("serialization")
-- Usa o componente data ou implementação própria
local serial = proxy("data")

-- Como não temos serialization do OpenOS, usamos uma implementação mínima
local function serialize(val)
    local t = type(val)
    if t == "nil"     then return "nil"
    elseif t == "boolean" then return tostring(val)
    elseif t == "number"  then return tostring(val)
    elseif t == "string"  then return string.format("%q", val)
    elseif t == "table"   then
        local s = "{"
        for k, v in pairs(val) do
            if type(k) == "string" then
                s = s .. "[" .. string.format("%q",k) .. "]=" .. serialize(v) .. ","
            else
                s = s .. "[" .. tostring(k) .. "]=" .. serialize(v) .. ","
            end
        end
        return s .. "}"
    end
    return "nil"
end

local function unserialize(s)
    local fn = load("return " .. s)
    if fn then return fn() end
    return nil
end

-- ----------------------------------------------------------------
-- Componentes
-- ----------------------------------------------------------------
local dislocator = proxy("dislocator_advanced")
if not dislocator then
    computer.beep(440, 0.5)
    error("DislocatorAdvanced nao encontrado!")
end

-- Pega as duas linked cards
local tunnels = {}
for addr, _ in component.list("tunnel") do
    table.insert(tunnels, component.proxy(addr))
end

if #tunnels < 2 then
    computer.beep(880, 0.5)
    error("Precisa de 2 Linked Cards! Encontradas: " .. #tunnels)
end

local tunnelTablet, tunnelServer
if tunnels[1].getChannel() < tunnels[2].getChannel() then
    tunnelTablet = tunnels[1]
    tunnelServer = tunnels[2]
else
    tunnelTablet = tunnels[2]
    tunnelServer = tunnels[1]
end

-- Protocol inline
local P = {
    MSG_LIST    = "LIST",
    MSG_ADD     = "ADD",
    MSG_EDIT    = "EDIT",
    MSG_REMOVE  = "REMOVE",
    MSG_GET     = "GET",
    MSG_MISSION = "MISSION",
    MSG_OK      = "OK",
    MSG_ERROR   = "ERROR",
    MSG_LOG     = "LOG",
    MSG_REPLY   = "REPLY",
    WAYPOINT_BASE = "base",
}

-- ----------------------------------------------------------------
-- Log
-- ----------------------------------------------------------------
local function log(text, msgType)
    msgType = msgType or P.MSG_LOG
    tunnelTablet.send(serialize({ replyType = msgType, text = text }))
end

-- ----------------------------------------------------------------
-- Relay para server
-- ----------------------------------------------------------------
local function relayToServer(msgType, data)
    tunnelServer.send(serialize({ type = msgType, data = data or {} }))
    local deadline = computer.uptime() + 5
    while computer.uptime() < deadline do
        local ev, _, _, _, _, raw = computer.pullSignal(1)
        if ev == "modem_message" and raw then
            local resp = unserialize(raw)
            if resp and resp.replyType == P.MSG_REPLY then
                return resp
            end
        end
    end
    return nil, "timeout"
end

-- ----------------------------------------------------------------
-- Teleporte por nome
-- ----------------------------------------------------------------
local function teleportTo(name)
    local targets = dislocator.getTargets()
    for i, t in ipairs(targets) do
        if t.name == name then
            dislocator.setSelected(i - 1)
            local ok, reason = dislocator.activate()
            if ok then return true end
            return false, tostring(reason)
        end
    end
    return false, "waypoint nao encontrado: " .. name
end

-- ----------------------------------------------------------------
-- Teleporte para coordenadas
-- ----------------------------------------------------------------
local TEMP_SLOT = 0

local function teleportToCoords(x, y, z, label)
    local targets = dislocator.getTargets()
    if #targets == 0 then
        dislocator.addTarget(x, y, z, 0, label)
    else
        dislocator.setTarget(TEMP_SLOT, x, y, z, 0, label)
    end
    dislocator.setSelected(TEMP_SLOT)
    local ok, reason = dislocator.activate()
    if ok then return true end
    return false, tostring(reason)
end

-- ----------------------------------------------------------------
-- Coleta (placeholders)
-- ----------------------------------------------------------------
local armorCollect = {}

armorCollect[1] = function()
    log("Coletando armadura 1...")
    local deadline = computer.uptime() + 1
    while computer.uptime() < deadline do computer.pullSignal(0.1) end
    return true
end

armorCollect[2] = function()
    log("Coletando armadura 2...")
    local deadline = computer.uptime() + 1
    while computer.uptime() < deadline do computer.pullSignal(0.1) end
    return true
end

-- ----------------------------------------------------------------
-- Entrega (placeholder)
-- ----------------------------------------------------------------
local function deliver()
    log("Entregando ao player...")
    local deadline = computer.uptime() + 1
    while computer.uptime() < deadline do computer.pullSignal(0.1) end
    return true
end

-- ----------------------------------------------------------------
-- Execução da missão
-- ----------------------------------------------------------------
local function executeMission(data)
    local armorId = data.armor_id
    log("Missao ID=" .. armorId)

    local resp, err = relayToServer(P.MSG_GET, { id = armorId })
    if not resp or not resp.ok then
        log("Erro server: " .. tostring(err or resp and resp.error), P.MSG_ERROR)
        return false
    end

    local armor = resp.armor
    log("Indo buscar: " .. armor.name)

    local ok2, err2 = teleportToCoords(armor.x, armor.y, armor.z, "_armor")
    if not ok2 then log("Falha tp: "..tostring(err2), P.MSG_ERROR) return false end
    log("Chegou.")

    local fn = armorCollect[armorId]
    if not fn then log("Sem coleta para ID="..armorId, P.MSG_ERROR) return false end
    if not fn() then log("Falha coleta.", P.MSG_ERROR) return false end

    log("Indo entregar...")
    local ok4, err4 = teleportToCoords(data.dx, data.dy, data.dz, "_delivery")
    if not ok4 then log("Falha tp: "..tostring(err4), P.MSG_ERROR) return false end

    if not deliver() then log("Falha entrega.", P.MSG_ERROR) return false end

    log("Voltando para base...")
    local ok6, err6 = teleportTo(P.WAYPOINT_BASE)
    if not ok6 then log("Falha base: "..tostring(err6), P.MSG_ERROR) return false end

    log("Missao concluida!", P.MSG_OK)
    return true
end

-- ----------------------------------------------------------------
-- Loop principal
-- ----------------------------------------------------------------
-- Sinaliza que está ativo
computer.beep(660, 0.2)
log("Drone ativo. Tablet:" .. tunnelTablet.getChannel() .. " Server:" .. tunnelServer.getChannel())

while true do
    local ev, _, _, _, _, raw = computer.pullSignal(1)
    if ev == "modem_message" and raw then
        local msg = unserialize(raw)
        if msg then
            if msg.type == P.MSG_MISSION then
                local ok = executeMission(msg.data or {})
                if not ok then log("Missao com erro.", P.MSG_ERROR) end
            elseif msg.type then
                -- Relay CRUD para server
                local resp, err = relayToServer(msg.type, msg.data)
                if not resp then
                    resp = { ok = false, error = tostring(err), replyType = P.MSG_REPLY }
                end
                resp.replyType = P.MSG_REPLY
                tunnelTablet.send(serialize(resp))
            end
        end
    end
end
