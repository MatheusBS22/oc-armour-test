-- tablet.lua
-- Roda no tablet. Usa Linked Card (tunnel) para comunicar
-- com o server e com o drone.
-- Requer: tunnel, navigation

local component = require("component")
local event     = require("event")
local serial    = require("serialization")
local term      = require("term")
local P         = dofile("/home/protocol.lua")

-- ----------------------------------------------------------------
-- Verifica componentes
-- ----------------------------------------------------------------
if not component.isAvailable("tunnel") then
    error("Linked Card (tunnel) não encontrada no tablet!")
end
if not component.isAvailable("navigation") then
    error("Navigation Upgrade não encontrado no tablet!")
end

local tunnel = component.tunnel
local nav    = component.navigation

-- ----------------------------------------------------------------
-- Helpers de UI
-- ----------------------------------------------------------------

local W = 50

local function cls()
    term.clear()
    term.setCursor(1, 1)
end

local function line(char)
    print(string.rep(char or "─", W))
end

local function header(title)
    cls()
    line("═")
    local pad = math.floor((W - #title - 2) / 2)
    print(string.rep(" ", pad) .. "[ " .. title .. " ]")
    line("═")
    print("")
end

local function prompt(msg, default)
    io.write(msg)
    if default ~= nil then io.write("[" .. tostring(default) .. "] ") end
    local input = io.read()
    if input == "" and default ~= nil then return default end
    return input
end

local function confirm(msg)
    io.write(msg .. " (s/n): ")
    local r = io.read()
    return r == "s" or r == "S"
end

local function pause()
    io.write("\nPressione ENTER para continuar...")
    io.read()
end

-- ----------------------------------------------------------------
-- Comunicação com o server via Linked Card
--
-- Linked Card: tunnel.send(data) envia, evento modem_message recebe
-- Identificamos respostas do server pelo campo replyType = MSG_REPLY
-- Identificamos status do drone pelo campo replyType = MSG_LOG/OK/ERROR
-- ----------------------------------------------------------------

local TIMEOUT = 5

local function request(msgType, data)
    tunnel.send(serial.serialize({ type = msgType, data = data or {} }))

    local deadline = require("computer").uptime() + TIMEOUT
    while require("computer").uptime() < deadline do
        local _, _, _, _, _, raw = event.pull(1, "modem_message")
        if raw then
            local ok, resp = pcall(serial.unserialize, raw)
            if ok and resp and resp.replyType == P.MSG_REPLY then
                return resp
            end
        end
    end
    return nil, "Servidor não respondeu (timeout)"
end

-- ----------------------------------------------------------------
-- Helpers
-- ----------------------------------------------------------------

local function listArmors()
    local resp, err = request(P.MSG_LIST)
    if not resp then return nil, err end
    if not resp.ok then return nil, resp.error end
    return resp.armors
end

local function getPosition()
    local x, y, z = nav.getPosition()
    return math.floor(x), math.floor(y), math.floor(z)
end

-- ----------------------------------------------------------------
-- Telas CRUD
-- ----------------------------------------------------------------

local function showList(armors)
    if #armors == 0 then
        print("  (nenhuma armadura cadastrada)")
    else
        print(string.format("  %-4s %-20s %6s %6s %6s", "ID", "NOME", "X", "Y", "Z"))
        line()
        for _, a in ipairs(armors) do
            print(string.format("  %-4d %-20s %6d %6d %6d",
                a.id, a.name, a.x, a.y, a.z))
        end
    end
    print("")
end

local function screenAdd()
    header("ADICIONAR ARMADURA")
    local x, y, z = getPosition()
    print(string.format("  Posição atual: X=%d Y=%d Z=%d", x, y, z))
    print("  (ENTER para usar posição atual)")
    print("")

    local name = prompt("  Nome: ")
    if name == "" then print("  Nome obrigatório.") pause() return end

    local px = tonumber(prompt("  X: ", x))
    local py = tonumber(prompt("  Y: ", y))
    local pz = tonumber(prompt("  Z: ", z))

    if not px or not py or not pz then
        print("  Coordenadas inválidas.") pause() return
    end

    local resp, err = request(P.MSG_ADD, { name=name, x=px, y=py, z=pz })
    if not resp then
        print("  ERRO: " .. tostring(err))
    elseif not resp.ok then
        print("  ERRO: " .. resp.error)
    else
        print(string.format("\n  ✓ '%s' cadastrada com ID=%d", resp.armor.name, resp.armor.id))
    end
    pause()
end

local function screenEdit(armors)
    header("EDITAR ARMADURA")
    showList(armors)

    local id = tonumber(prompt("  ID para editar (0 = cancelar): "))
    if not id or id == 0 then return end

    local resp, err = request(P.MSG_GET, { id=id })
    if not resp or not resp.ok then
        print("  ERRO: " .. tostring(err or resp and resp.error))
        pause() return
    end

    local a = resp.armor
    local x, y, z = getPosition()
    print(string.format("\n  Editando: %s | Posição atual: X=%d Y=%d Z=%d", a.name, x, y, z))
    print("")

    local name = prompt("  Nome:  ", a.name)
    local px   = tonumber(prompt("  X:     ", a.x))
    local py   = tonumber(prompt("  Y:     ", a.y))
    local pz   = tonumber(prompt("  Z:     ", a.z))

    local resp2, err2 = request(P.MSG_EDIT, { id=id, name=name, x=px, y=py, z=pz })
    if not resp2 then
        print("  ERRO: " .. tostring(err2))
    elseif not resp2.ok then
        print("  ERRO: " .. resp2.error)
    else
        print("  ✓ Atualizado.")
    end
    pause()
end

local function screenRemove(armors)
    header("REMOVER ARMADURA")
    showList(armors)

    local id = tonumber(prompt("  ID para remover (0 = cancelar): "))
    if not id or id == 0 then return end
    if not confirm("  Confirma?") then return end

    local resp, err = request(P.MSG_REMOVE, { id=id })
    if not resp then
        print("  ERRO: " .. tostring(err))
    elseif not resp.ok then
        print("  ERRO: " .. resp.error)
    else
        print("  ✓ Removida.")
    end
    pause()
end

local function screenSendMission(armors)
    header("ENVIAR MISSÃO AO DRONE")

    if #armors == 0 then
        print("  Nenhuma armadura cadastrada.")
        pause() return
    end

    showList(armors)

    local id = tonumber(prompt("  ID da armadura (0 = cancelar): "))
    if not id or id == 0 then return end

    local x, y, z = getPosition()
    print(string.format("\n  Entrega na sua posição: X=%d Y=%d Z=%d", x, y, z))

    if not confirm("  Enviar missão?") then return end

    tunnel.send(serial.serialize({
        type = P.MSG_MISSION,
        data = { x=x, y=y, z=z, armor_id=id }
    }))

    print("\n  ✓ Missão enviada! Aguardando drone...")
    print("")

    -- Escuta status do drone por 60 segundos
    local deadline = require("computer").uptime() + 60
    while require("computer").uptime() < deadline do
        local _, _, _, _, _, raw = event.pull(2, "modem_message")
        if raw then
            local ok, msg = pcall(serial.unserialize, raw)
            if ok and msg and msg.replyType and msg.replyType ~= P.MSG_REPLY then
                local icon = msg.replyType == P.MSG_OK and "✓" or
                             msg.replyType == P.MSG_ERROR and "✗" or "·"
                print("  " .. icon .. " " .. tostring(msg.text or ""))
                if msg.replyType == P.MSG_OK or msg.replyType == P.MSG_ERROR then
                    break
                end
            end
        end
    end

    pause()
end

-- ----------------------------------------------------------------
-- Menu principal
-- ----------------------------------------------------------------

local function main()
    while true do
        local armors, err = listArmors()

        header("SISTEMA DE ARMADURAS")

        if not armors then
            print("  [!] Servidor offline: " .. tostring(err))
            print("")
            armors = {}
        else
            print("  Armaduras cadastradas: " .. #armors)
            print("")
        end

        line()
        print("  1. Listar armaduras")
        print("  2. Adicionar armadura")
        print("  3. Editar armadura")
        print("  4. Remover armadura")
        line()
        print("  5. Enviar missão ao drone")
        line()
        print("  0. Sair")
        print("")

        local op = prompt("  Opção: ")

        if     op == "1" then header("ARMADURAS") showList(armors) pause()
        elseif op == "2" then screenAdd()
        elseif op == "3" then screenEdit(armors)
        elseif op == "4" then screenRemove(armors)
        elseif op == "5" then screenSendMission(armors)
        elseif op == "0" then cls() return
        end
    end
end

main()
