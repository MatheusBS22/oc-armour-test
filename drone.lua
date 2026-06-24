-- drone.lua
-- Roda no drone. Recebe missões do tablet e executa:
--   1. Teleporta para o local da armadura (via DislocatorAdvanced)
--   2. Executa a função de coleta da armadura (placeholder por ora)
--   3. Teleporta para a posição de entrega enviada pelo tablet
--   4. Executa a função de entrega (placeholder por ora)
--   5. Teleporta de volta para "base"

local component = require("component")
local event     = require("event")
local serial    = require("serialization")
local P         = require("protocol")

-- ----------------------------------------------------------------
-- Verifica componentes
-- ----------------------------------------------------------------
if not component.isAvailable("modem") then
    error("Modem não encontrado no drone!")
end
if not component.isAvailable("dislocator_advanced") then
    error("DislocatorAdvanced não encontrado no inventário do drone!")
end

local modem      = component.modem
local dislocator = component.dislocator_advanced

modem.open(P.PORT_DRONE)

-- ----------------------------------------------------------------
-- Helper de log — envia status para o tablet e imprime local
-- ----------------------------------------------------------------
local tabletAddr = nil  -- endereço do tablet que enviou a missão

local function log(text, msgType)
    msgType = msgType or P.MSG_LOG
    print("[drone] " .. text)
    if tabletAddr then
        modem.send(tabletAddr, P.PORT_STATUS, serial.serialize({
            type = msgType,
            text = text,
        }))
    end
end

-- ----------------------------------------------------------------
-- Teleporte via DislocatorAdvanced
--
-- Procura um destino pelo nome na lista do dislocator e teleporta.
-- Retorna true/false + mensagem de erro.
-- ----------------------------------------------------------------
local function teleportTo(name)
    local targets = dislocator.getTargets()

    -- Procura o destino pelo nome
    for i, t in ipairs(targets) do
        if t.name == name then
            dislocator.setSelected(i - 1)  -- índice 0-based
            local ok, reason = dislocator.activate()
            if ok then
                return true
            else
                return false, "activate() falhou: " .. tostring(reason)
            end
        end
    end

    return false, "Waypoint '" .. name .. "' não encontrado no dislocator"
end

-- ----------------------------------------------------------------
-- Adiciona (ou sobrescreve slot 0) um destino temporário e teleporta
-- Usado para ir a posições dinâmicas (armadura, entrega)
-- ----------------------------------------------------------------
local TEMP_SLOT = 0  -- índice 0 reservado para destinos temporários

local function teleportToCoords(x, y, z, label)
    local targets = dislocator.getTargets()

    if #targets == 0 then
        dislocator.addTarget(x, y, z, 0, label)
    else
        dislocator.setTarget(TEMP_SLOT, x, y, z, 0, label)
    end

    dislocator.setSelected(TEMP_SLOT)
    local ok, reason = dislocator.activate()
    if ok then
        return true
    else
        return false, "activate() falhou: " .. tostring(reason)
    end
end

-- ----------------------------------------------------------------
-- Funções de coleta de armadura (placeholders)
--
-- Cada ID de armadura tem sua própria função de coleta.
-- Implemente aqui a lógica específica de cada armadura:
--   - Abrir baú, pegar itens, etc.
-- ----------------------------------------------------------------

local armorCollect = {}

-- Armadura ID 1
armorCollect[1] = function()
    -- TODO: implementar coleta da armadura 1
    -- Exemplo futuro:
    --   drone.suck(1)  -- pega item à frente
    --   drone.suck(2)  -- pega item à direita
    log("  [placeholder] Coletando armadura 1...")
    os.sleep(1)  -- simula tempo de coleta
    return true
end

-- Armadura ID 2
armorCollect[2] = function()
    -- TODO: implementar coleta da armadura 2
    log("  [placeholder] Coletando armadura 2...")
    os.sleep(1)
    return true
end

-- ----------------------------------------------------------------
-- Função de entrega (placeholder)
--
-- Chamada depois que o drone chegou na posição do tablet (player).
-- Aqui você vai definir se dropa os itens, abre uma GUI, etc.
-- ----------------------------------------------------------------
local function deliver()
    -- TODO: implementar entrega
    -- Exemplos futuros:
    --   drone.drop(1)   -- dropa item para o player
    --   drone.use()     -- usa item (abre baú, etc.)
    log("  [placeholder] Entregando armadura ao player...")
    os.sleep(1)
    return true
end

-- ----------------------------------------------------------------
-- Execução da missão
-- ----------------------------------------------------------------
local function executeMission(data)
    local armorId    = data.armor_id
    local deliveryX  = data.x
    local deliveryY  = data.y
    local deliveryZ  = data.z

    log("Missão iniciada: armadura ID=" .. armorId)

    -- 1. Busca a armadura no servidor para saber as coordenadas
    --    (o tablet já mandou o armor_id, mas não as coords da armadura)
    --    Então pedimos ao server diretamente
    log("Consultando servidor para localização da armadura...")
    modem.broadcast(P.PORT_SERVER, serial.serialize({
        type = P.MSG_GET,
        data = { id = armorId }
    }))

    local _, _, _, port, _, raw = event.pull(5, "modem_message")
    if not raw or port ~= P.PORT_REPLY then
        log("Servidor não respondeu ao consultar armadura.", P.MSG_ERROR)
        return false
    end

    local ok, resp = pcall(serial.unserialize, raw)
    if not ok or not resp or not resp.ok then
        log("Erro ao obter armadura: " .. tostring(resp and resp.error or "?"), P.MSG_ERROR)
        return false
    end

    local armor = resp.armor
    log(string.format("Armadura '%s' em X=%d Y=%d Z=%d", armor.name, armor.x, armor.y, armor.z))

    -- 2. Teleporta para o local da armadura
    log("Teleportando para o local da armadura...")
    local ok2, err2 = teleportToCoords(armor.x, armor.y, armor.z, "_armor_temp")
    if not ok2 then
        log("Falha no teleporte para armadura: " .. tostring(err2), P.MSG_ERROR)
        return false
    end
    log("Chegou no local da armadura.")

    -- 3. Coleta a armadura (função específica por ID)
    local collectFn = armorCollect[armorId]
    if not collectFn then
        log("Nenhuma função de coleta para armadura ID=" .. armorId, P.MSG_ERROR)
        return false
    end

    local ok3 = collectFn()
    if not ok3 then
        log("Falha na coleta da armadura.", P.MSG_ERROR)
        return false
    end
    log("Armadura coletada.")

    -- 4. Teleporta para a posição de entrega (onde está o player/tablet)
    log(string.format("Teleportando para entrega em X=%d Y=%d Z=%d", deliveryX, deliveryY, deliveryZ))
    local ok4, err4 = teleportToCoords(deliveryX, deliveryY, deliveryZ, "_delivery_temp")
    if not ok4 then
        log("Falha no teleporte para entrega: " .. tostring(err4), P.MSG_ERROR)
        return false
    end
    log("Chegou no ponto de entrega.")

    -- 5. Entrega a armadura
    local ok5 = deliver()
    if not ok5 then
        log("Falha na entrega.", P.MSG_ERROR)
        return false
    end
    log("Entrega concluída.")

    -- 6. Volta para base pelo waypoint nomeado "base"
    log("Retornando para base...")
    local ok6, err6 = teleportTo(P.WAYPOINT_BASE)
    if not ok6 then
        log("Falha ao retornar para base: " .. tostring(err6), P.MSG_ERROR)
        return false
    end

    log("Missão concluída! De volta à base.", P.MSG_OK)
    return true
end

-- ----------------------------------------------------------------
-- Loop principal
-- ----------------------------------------------------------------
print("╔══════════════════════════════╗")
print("║        DRONE ATIVO           ║")
print("╚══════════════════════════════╝")
print("Aguardando missões na porta " .. P.PORT_DRONE .. "...")

while true do
    local _, _, sender, port, _, raw = event.pull("modem_message")

    if port == P.PORT_DRONE and raw then
        local ok, msg = pcall(serial.unserialize, raw)

        if ok and msg and msg.type == P.MSG_MISSION then
            tabletAddr = sender  -- guarda para mandar status de volta
            log("Missão recebida de " .. sender:sub(1, 8))

            local success = executeMission(msg.data or {})
            if not success then
                log("Missão encerrada com erro.", P.MSG_ERROR)
            end
            tabletAddr = nil
        end
    end
end
