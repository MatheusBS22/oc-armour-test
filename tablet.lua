-- tablet.lua
-- Roda no tablet. Interface de texto para:
--   - Gerenciar armaduras (CRUD via server)
--   - Pegar posição atual via Navigation Upgrade
--   - Enviar missão para o drone

local component = require("component")
local event     = require("event")
local serial    = require("serialization")
local term      = require("term")
local P         = require("protocol")

-- ----------------------------------------------------------------
-- Verifica componentes
-- ----------------------------------------------------------------
if not component.isAvailable("modem") then
    error("Modem não encontrado no tablet!")
end
if not component.isAvailable("navigation") then
    error("Navigation Upgrade não encontrado no tablet!")
end

local modem = component.modem
local nav   = component.navigation

modem.open(P.PORT_REPLY)
modem.open(P.PORT_STATUS)

-- ----------------------------------------------------------------
-- Helpers de UI
-- ----------------------------------------------------------------

local W = 50  -- largura da caixa

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
    if default then io.write("[" .. tostring(default) .. "] ") end
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
-- Comunicação com o server
-- ----------------------------------------------------------------

local TIMEOUT = 5  -- segundos

local function request(msgType, data)
    local msg = serial.serialize({ type = msgType, data = data or {} })
    modem.broadcast(P.PORT_SERVER, msg)

    -- Aguarda resposta
    local _, _, _, port, _, raw = event.pull(TIMEOUT, "modem_message")
    if not raw then
        return nil, "Servidor não respondeu (timeout)"
    end
    if port ~= P.PORT_REPLY then
        return nil, "Resposta em porta errada"
    end

    local ok, resp = pcall(serial.unserialize, raw)
    if not ok then
        return nil, "Resposta malformada"
    end
    return resp
end

-- ----------------------------------------------------------------
-- Funções CRUD
-- ----------------------------------------------------------------

local function listArmors()
    local resp, err = request(P.MSG_LIST)
    if not resp then return nil, err end
    if not resp.ok then return nil, resp.error end
    return resp.armors
end

local function getPosition()
    -- Navigation retorna posição relativa ao mapa inserido no upgrade.
    -- Se não tiver mapa, retorna posição absoluta mesmo assim no OC.
    local x, y, z = nav.getPosition()
    return math.floor(x), math.floor(y), math.floor(z)
end

-- ----------------------------------------------------------------
-- Telas do CRUD
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
    print("  (deixe em branco para usar a posição atual)")
    print("")

    local name = prompt("  Nome da armadura: ")
    if name == "" then print("  Nome obrigatório.") pause() return end

    local px = tonumber(prompt("  X: ", x))
    local py = tonumber(prompt("  Y: ", y))
    local pz = tonumber(prompt("  Z: ", z))

    if not px or not py or not pz then
        print("  Coordenadas inválidas.")
        pause()
        return
    end

    local resp, err = request(P.MSG_ADD, { name = name, x = px, y = py, z = pz })
    if not resp then
        print("  ERRO: " .. err)
    elseif not resp.ok then
        print("  ERRO: " .. resp.error)
    else
        print(string.format("\n  ✓ Armadura '%s' cadastrada com ID=%d", resp.armor.name, resp.armor.id))
    end
    pause()
end

local function screenEdit(armors)
    header("EDITAR ARMADURA")
    showList(armors)

    local id = tonumber(prompt("  ID para editar (0 = cancelar): "))
    if not id or id == 0 then return end

    local resp, err = request(P.MSG_GET, { id = id })
    if not resp or not resp.ok then
        print("  ERRO: " .. (err or resp and resp.error or "?"))
        pause()
        return
    end

    local a = resp.armor
    print(string.format("\n  Editando: %s (ID=%d)", a.name, a.id))
    print("  (deixe em branco para manter o valor atual)")
    print("")

    local x, y, z = getPosition()
    print(string.format("  Posição atual do tablet: X=%d Y=%d Z=%d", x, y, z))
    print("")

    local name = prompt("  Nome:  ", a.name)
    local px   = tonumber(prompt("  X:     ", a.x))
    local py   = tonumber(prompt("  Y:     ", a.y))
    local pz   = tonumber(prompt("  Z:     ", a.z))

    local resp2, err2 = request(P.MSG_EDIT, {
        id   = id,
        name = name,
        x    = px,
        y    = py,
        z    = pz,
    })

    if not resp2 then
        print("  ERRO: " .. err2)
    elseif not resp2.ok then
        print("  ERRO: " .. resp2.error)
    else
        print(string.format("\n  ✓ Armadura ID=%d atualizada.", id))
    end
    pause()
end

local function screenRemove(armors)
    header("REMOVER ARMADURA")
    showList(armors)

    local id = tonumber(prompt("  ID para remover (0 = cancelar): "))
    if not id or id == 0 then return end

    if not confirm("  Confirma remoção do ID=" .. id .. "?") then return end

    local resp, err = request(P.MSG_REMOVE, { id = id })
    if not resp then
        print("  ERRO: " .. err)
    elseif not resp.ok then
        print("  ERRO: " .. resp.error)
    else
        print(string.format("\n  ✓ Armadura '%s' removida.", resp.armor.name))
    end
    pause()
end

local function screenSendMission(armors)
    header("ENVIAR MISSÃO AO DRONE")

    if #armors == 0 then
        print("  Nenhuma armadura cadastrada.")
        pause()
        return
    end

    showList(armors)

    local id = tonumber(prompt("  ID da armadura desejada (0 = cancelar): "))
    if not id or id == 0 then return end

    -- Pega posição atual do tablet como destino de entrega
    local x, y, z = getPosition()
    print(string.format("\n  Posição de entrega (sua posição atual): X=%d Y=%d Z=%d", x, y, z))

    if not confirm("  Enviar missão?") then return end

    local mission = serial.serialize({
        type = P.MSG_MISSION,
        data = {
            x        = x,
            y        = y,
            z        = z,
            armor_id = id,
        }
    })

    modem.broadcast(P.PORT_DRONE, mission)
    print("\n  ✓ Missão enviada! Aguardando status do drone...")
    print("")

    -- Fica escutando status do drone por até 60 segundos
    local deadline = computer.uptime() + 60
    while computer.uptime() < deadline do
        local _, _, _, port, _, raw = event.pull(2, "modem_message")
        if port == P.PORT_STATUS and raw then
            local ok, msg = pcall(serial.unserialize, raw)
            if ok and msg then
                local icon = msg.type == P.MSG_OK and "✓" or
                             msg.type == P.MSG_ERROR and "✗" or "·"
                print("  " .. icon .. " " .. tostring(msg.text or ""))
                -- Para de escutar quando receber OK ou ERROR final
                if msg.type == P.MSG_OK or msg.type == P.MSG_ERROR then
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
        -- Carrega lista a cada iteração para manter atualizado
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

        if op == "1" then
            header("ARMADURAS CADASTRADAS")
            showList(armors)
            pause()
        elseif op == "2" then
            screenAdd()
        elseif op == "3" then
            screenEdit(armors)
        elseif op == "4" then
            screenRemove(armors)
        elseif op == "5" then
            screenSendMission(armors)
        elseif op == "0" then
            cls()
            print("Encerrando tablet...")
            modem.close(P.PORT_REPLY)
            modem.close(P.PORT_STATUS)
            return
        end
    end
end

main()
