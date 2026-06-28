-- drone.lua — roda no drone
-- Sem dependência de arquivos externos — protocol embutido
-- 2 Linked Cards: tunnelTablet (Par 1) e tunnelServer (Par 2)

local component = require("component")
local event     = require("event")
local serial    = require("serialization")

-- ----------------------------------------------------------------
-- Protocol embutido (sem dofile)
-- ----------------------------------------------------------------
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
-- Verifica componentes
-- ----------------------------------------------------------------
if not component.isAvailable("dislocator_advanced") then
    error("DislocatorAdvanced não encontrado!")
end

local tunnels = {}
for addr, _ in component.list("tunnel") do
    table.insert(tunnels, component.proxy(addr))
end

if #tunnels < 2 then
    error("Precisa de 2 Linked Cards! Encontradas: " .. #tunnels)
end

-- Card de menor canal = tablet, maior = server
local tunnelTablet, tunnelServer
if tunnels[1].getChannel() < tunnels[2].getChannel() then
    tunnelTablet = tunnels[1]
    tunnelServer = tunnels[2]
else
    tunnelTablet = tunnels[2]
    tunnelServer = tunnels[1]
end

local dislocator = component.dislocator_advanced

-- ----------------------------------------------------------------
-- Log para o tablet
-- ----------------------------------------------------------------
local function log(text, msgType)
    msgType = msgType or P.MSG_LOG
    print("[drone] " .. text)
    tunnelTablet.send(serial.serialize({ replyType = msgType, text = text }))
end

-- ----------------------------------------------------------------
-- Relay tablet → server
-- ----------------------------------------------------------------
local function relayToServer(msgType, data)
    tunnelServer.send(serial.serialize({ type = msgType, data = data or {} }))
    local deadline = require("computer").uptime() + 5
    while require("computer").uptime() < deadline do
        local _, _, _, _, _, raw = event.pull(1, "modem_message")
        if raw then
            local ok, resp = pcall(serial.unserialize, raw)
            if ok and resp and resp.replyType == P.MSG_REPLY then
                return resp
            end
        end
    end
    return nil, "Server não respondeu"
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
    return false, "Waypoint '" .. name .. "' não encontrado"
end

-- ----------------------------------------------------------------
-- Teleporte para coordenadas dinâmicas
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
-- Coleta por armadura (placeholders)
-- ----------------------------------------------------------------
local armorCollect = {}

armorCollect[1] = function()
    log("  [placeholder] Coletando armadura 1...")
    os.sleep(1)
    return true
end

armorCollect[2] = function()
    log("  [placeholder] Coletando armadura 2...")
    os.sleep(1)
    return true
end

-- ----------------------------------------------------------------
-- Entrega (placeholder)
-- ----------------------------------------------------------------
local function deliver()
    log("  [placeholder] Entregando ao player...")
    os.sleep(1)
    return true
end

-- ----------------------------------------------------------------
-- Execução da missão
-- ----------------------------------------------------------------
local function executeMission(data)
    local armorId = data.armor_id
    log("Missão: armadura ID=" .. armorId)

    -- Busca coords da armadura
    log("Consultando server...")
    local resp, err = relayToServer(P.MSG_GET, { id = armorId })
    if not resp or not resp.ok then
        log("Erro: " .. tostring(err or resp and resp.error), P.MSG_ERROR)
        return false
    end

    local armor = resp.armor
    log(string.format("'%s' em X=%d Y=%d Z=%d", armor.name, armor.x, armor.y, armor.z))

    -- Vai buscar
    log("Teleportando para armadura...")
    local ok2, err2 = teleportToCoords(armor.x, armor.y, armor.z, "_armor")
    if not ok2 then log("Falha: "..tostring(err2), P.MSG_ERROR) return false end
    log("Chegou.")

    -- Coleta
    local fn = armorCollect[armorId]
    if not fn then log("Sem função para ID="..armorId, P.MSG_ERROR) return false end
    if not fn() then log("Falha na coleta.", P.MSG_ERROR) return false end
    log("Coletado.")

    -- Vai entregar
    log(string.format("Indo entregar em X=%d Y=%d Z=%d", data.dx, data.dy, data.dz))
    local ok4, err4 = teleportToCoords(data.dx, data.dy, data.dz, "_delivery")
    if not ok4 then log("Falha: "..tostring(err4), P.MSG_ERROR) return false end
    log("Chegou na entrega.")

    -- Entrega
    if not deliver() then log("Falha na entrega.", P.MSG_ERROR) return false end
    log("Entregue.")

    -- Volta para base
    log("Retornando...")
    local ok6, err6 = teleportTo(P.WAYPOINT_BASE)
    if not ok6 then log("Falha: "..tostring(err6), P.MSG_ERROR) return false end

    log("Missão concluída!", P.MSG_OK)
    return true
end

-- ----------------------------------------------------------------
-- Loop principal
-- ----------------------------------------------------------------
print("Drone ativo")
print("Tablet: " .. tunnelTablet.getChannel())
print("Server: " .. tunnelServer.getChannel())

while true do
    local _, _, _, _, _, raw = event.pull("modem_message")
    if raw then
        local ok, msg = pcall(serial.unserialize, raw)
        if ok and msg then
            if msg.type == P.MSG_MISSION then
                local success = executeMission(msg.data or {})
                if not success then log("Missão com erro.", P.MSG_ERROR) end
            elseif msg.type then
                -- Relay CRUD para o server
                local resp, err = relayToServer(msg.type, msg.data)
                if not resp then
                    resp = { ok = false, error = tostring(err), replyType = P.MSG_REPLY }
                end
                resp.replyType = P.MSG_REPLY
                tunnelTablet.send(serial.serialize(resp))
            end
        end
    end
end
