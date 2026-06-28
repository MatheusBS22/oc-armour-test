-- drone.lua — roda no drone
-- 2 Linked Cards:
--   tunnelTablet → fala com o tablet (Par 1)
--   tunnelServer → fala com o PC server (Par 2)
--
-- O drone é o hub: recebe missões do tablet,
-- consulta o server, executa, reporta status ao tablet.

local component = require("component")
local event     = require("event")
local serial    = require("serialization")
local P         = dofile("/home/protocol.lua")

if not component.isAvailable("dislocator_advanced") then
    error("DislocatorAdvanced não encontrado!")
end

-- Pega as duas linked cards
local tunnels = {}
for addr, _ in component.list("tunnel") do
    table.insert(tunnels, component.proxy(addr))
end

if #tunnels < 2 then
    error("Precisa de 2 Linked Cards no drone! Encontradas: " .. #tunnels)
end

-- A card com canal menor fala com o tablet, a maior com o server
-- (convenção — pode trocar se necessário)
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
-- Relay de requisições CRUD do tablet para o server
-- ----------------------------------------------------------------

local function relayToServer(msgType, data)
    tunnelServer.send(serial.serialize({ type = msgType, data = data or {} }))
    local deadline = require("computer").uptime() + 5
    while require("computer").uptime() < deadline do
        local _, _, sender, _, _, raw = event.pull(1, "modem_message")
        if raw then
            local ok, resp = pcall(serial.unserialize, raw)
            -- Resposta do server (vem pelo tunnelServer)
            if ok and resp and resp.replyType == P.MSG_REPLY then
                return resp
            end
        end
    end
    return nil, "Server não respondeu"
end

-- ----------------------------------------------------------------
-- Teleporte por nome de waypoint
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

    log("Missão recebida: armadura ID=" .. armorId)

    -- 1. Busca coords da armadura no server
    log("Consultando server...")
    local resp, err = relayToServer(P.MSG_GET, { id = armorId })
    if not resp or not resp.ok then
        log("Erro ao buscar armadura: " .. tostring(err or resp and resp.error), P.MSG_ERROR)
        return false
    end

    local armor = resp.armor
    log(string.format("Armadura '%s' em X=%d Y=%d Z=%d", armor.name, armor.x, armor.y, armor.z))

    -- 2. Teleporta para a armadura
    log("Teleportando para armadura...")
    local ok2, err2 = teleportToCoords(armor.x, armor.y, armor.z, "_armor")
    if not ok2 then log("Falha: "..tostring(err2), P.MSG_ERROR) return false end
    log("Chegou no local.")

    -- 3. Coleta
    local fn = armorCollect[armorId]
    if not fn then log("Sem função de coleta para ID="..armorId, P.MSG_ERROR) return false end
    if not fn() then log("Falha na coleta.", P.MSG_ERROR) return false end
    log("Coletado.")

    -- 4. Teleporta para entrega
    log(string.format("Indo entregar em X=%d Y=%d Z=%d", data.dx, data.dy, data.dz))
    local ok4, err4 = teleportToCoords(data.dx, data.dy, data.dz, "_delivery")
    if not ok4 then log("Falha: "..tostring(err4), P.MSG_ERROR) return false end
    log("Chegou na entrega.")

    -- 5. Entrega
    if not deliver() then log("Falha na entrega.", P.MSG_ERROR) return false end
    log("Entregue.")

    -- 6. Volta para base
    log("Retornando para base...")
    local ok6, err6 = teleportTo(P.WAYPOINT_BASE)
    if not ok6 then log("Falha: "..tostring(err6), P.MSG_ERROR) return false end

    log("Missão concluída!", P.MSG_OK)
    return true
end

-- ----------------------------------------------------------------
-- Loop principal — escuta tablet E server
-- ----------------------------------------------------------------

print("╔══════════════════════════════╗")
print("║        DRONE ATIVO           ║")
print("╚══════════════════════════════╝")
print("Canal tablet: " .. tunnelTablet.getChannel())
print("Canal server: " .. tunnelServer.getChannel())
print("Aguardando...")

while true do
    local _, _, _, _, _, raw = event.pull("modem_message")
    if raw then
        local ok, msg = pcall(serial.unserialize, raw)
        if ok and msg then
            if msg.type == P.MSG_MISSION then
                -- Missão vinda do tablet
                local success = executeMission(msg.data or {})
                if not success then log("Missão com erro.", P.MSG_ERROR) end

            elseif msg.type and msg.type ~= P.MSG_MISSION then
                -- Requisição CRUD vinda do tablet — faz relay para o server
                -- e devolve resposta ao tablet
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
