-- drone.lua
-- Roda no drone. Usa Linked Card (tunnel) para comunicar.
-- Fluxo: recebe missão → busca armadura → coleta (placeholder)
--        → entrega (placeholder) → volta para base

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
-- Log — envia status para o tablet
-- ----------------------------------------------------------------

local function log(text, msgType)
    msgType = msgType or P.MSG_LOG
    print("[drone] " .. text)
    tunnel.send(serial.serialize({
        replyType = msgType,
        text      = text,
    }))
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
    local armorId   = data.armor_id
    local deliveryX = data.x
    local deliveryY = data.y
    local deliveryZ = data.z

    log("Missão iniciada: armadura ID=" .. armorId)

    -- 1. Consulta o server pelas coords da armadura
    log("Consultando servidor...")
    tunnel.send(serial.serialize({ type = P.MSG_GET, data = { id = armorId } }))

    local resp = nil
    local deadline = require("computer").uptime() + 5
    while require("computer").uptime() < deadline do
        local _, _, _, _, _, raw = event.pull(1, "modem_message")
        if raw then
            local ok, msg = pcall(serial.unserialize, raw)
            if ok and msg and msg.replyType == P.MSG_REPLY then
                resp = msg
                break
            end
        end
    end

    if not resp or not resp.ok then
        log("Erro ao obter armadura: " .. tostring(resp and resp.error or "timeout"), P.MSG_ERROR)
        return false
    end

    local armor = resp.armor
    log(string.format("Armadura '%s' em X=%d Y=%d Z=%d", armor.name, armor.x, armor.y, armor.z))

    -- 2. Teleporta para o local da armadura
    log("Teleportando para armadura...")
    local ok2, err2 = teleportToCoords(armor.x, armor.y, armor.z, "_armor")
    if not ok2 then
        log("Falha: " .. tostring(err2), P.MSG_ERROR)
        return false
    end
    log("Chegou no local da armadura.")

    -- 3. Coleta
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

    -- 4. Teleporta para entrega
    log(string.format("Teleportando para entrega X=%d Y=%d Z=%d", deliveryX, deliveryY, deliveryZ))
    local ok4, err4 = teleportToCoords(deliveryX, deliveryY, deliveryZ, "_delivery")
    if not ok4 then
        log("Falha: " .. tostring(err4), P.MSG_ERROR)
        return false
    end
    log("Chegou no ponto de entrega.")

    -- 5. Entrega
    if not deliver() then
        log("Falha na entrega.", P.MSG_ERROR)
        return false
    end
    log("Entrega concluída.")

    -- 6. Volta para base
    log("Retornando para base...")
    local ok6, err6 = teleportTo(P.WAYPOINT_BASE)
    if not ok6 then
        log("Falha ao retornar: " .. tostring(err6), P.MSG_ERROR)
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
