-- drone.lua
-- Roda no drone. Usa 1 Linked Card para falar com o tablet.
-- Recebe missão completa (coords já incluídas) — não precisa
-- consultar o server diretamente.

local component = require("component")
local event     = require("event")
local serial    = require("serialization")
local P         = dofile("/home/protocol.lua")

-- ----------------------------------------------------------------
-- Verifica componentes
-- ----------------------------------------------------------------
if not component.isAvailable("tunnel") then
    error("Linked Card (tunnel) não encontrada no drone!")
end
if not component.isAvailable("dislocator_advanced") then
    error("DislocatorAdvanced não encontrado no inventário do drone!")
end

local tunnel     = component.tunnel
local dislocator = component.dislocator_advanced

-- ----------------------------------------------------------------
-- Log
-- ----------------------------------------------------------------

local function log(text, msgType)
    msgType = msgType or P.MSG_LOG
    print("[drone] " .. text)
    tunnel.send(serial.serialize({ replyType = msgType, text = text }))
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
            return false, "activate() falhou: " .. tostring(reason)
        end
    end
    return false, "Waypoint '" .. name .. "' não encontrado"
end

-- ----------------------------------------------------------------
-- Teleporte para coordenadas dinâmicas (slot 0 = temporário)
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
    return false, "activate() falhou: " .. tostring(reason)
end

-- ----------------------------------------------------------------
-- Funções de coleta por armadura (placeholders)
-- Implemente aqui a lógica de pegar a armadura no baú
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
-- Implemente aqui a lógica de entregar ao player
-- ----------------------------------------------------------------

local function deliver()
    log("  [placeholder] Entregando ao player...")
    os.sleep(1)
    return true
end

-- ----------------------------------------------------------------
-- Execução da missão
-- Recebe dados completos: armor_id, ax/ay/az (armadura), dx/dy/dz (entrega)
-- ----------------------------------------------------------------

local function executeMission(data)
    local armorId = data.armor_id
    local name    = data.armor_name or "armadura"

    log(string.format("Missão: '%s' (ID=%d)", name, armorId))

    -- 1. Teleporta para o local da armadura
    log(string.format("Indo buscar em X=%d Y=%d Z=%d", data.ax, data.ay, data.az))
    local ok1, err1 = teleportToCoords(data.ax, data.ay, data.az, "_armor")
    if not ok1 then
        log("Falha no teleporte: " .. tostring(err1), P.MSG_ERROR)
        return false
    end
    log("Chegou no local da armadura.")

    -- 2. Coleta
    local collectFn = armorCollect[armorId]
    if not collectFn then
        log("Sem função de coleta para ID=" .. armorId, P.MSG_ERROR)
        return false
    end
    if not collectFn() then
        log("Falha na coleta.", P.MSG_ERROR)
        return false
    end
    log("Armadura coletada.")

    -- 3. Teleporta para entrega
    log(string.format("Indo entregar em X=%d Y=%d Z=%d", data.dx, data.dy, data.dz))
    local ok3, err3 = teleportToCoords(data.dx, data.dy, data.dz, "_delivery")
    if not ok3 then
        log("Falha no teleporte: " .. tostring(err3), P.MSG_ERROR)
        return false
    end
    log("Chegou no ponto de entrega.")

    -- 4. Entrega
    if not deliver() then
        log("Falha na entrega.", P.MSG_ERROR)
        return false
    end
    log("Entrega concluída.")

    -- 5. Volta para base
    log("Retornando para base...")
    local ok5, err5 = teleportTo(P.WAYPOINT_BASE)
    if not ok5 then
        log("Falha ao retornar: " .. tostring(err5), P.MSG_ERROR)
        return false
    end

    log("Missão concluída!", P.MSG_OK)
    return true
end

-- ----------------------------------------------------------------
-- Loop principal
-- ----------------------------------------------------------------

print("╔══════════════════════════════╗")
print("║        DRONE ATIVO           ║")
print("╚══════════════════════════════╝")
print("Canal: " .. tunnel.getChannel())
print("Aguardando missões...")

while true do
    local _, _, _, _, _, raw = event.pull("modem_message")
    if raw then
        local ok, msg = pcall(serial.unserialize, raw)
        if ok and msg and msg.type == P.MSG_MISSION then
            log("Missão recebida!")
            local success = executeMission(msg.data or {})
            if not success then
                log("Missão encerrada com erro.", P.MSG_ERROR)
            end
        end
    end
end
