-- tablet.lua — roda no tablet
-- 1 Linked Card: fala com o drone (Par 1)
-- O drone faz relay das requisições ao server

local component = require("component")
local event     = require("event")
local serial    = require("serialization")
local term      = require("term")
local P         = dofile("/home/protocol.lua")

if not component.isAvailable("tunnel") then
    error("Linked Card não encontrada no tablet!")
end
if not component.isAvailable("navigation") then
    error("Navigation Upgrade não encontrado!")
end

local tunnel = component.tunnel
local nav    = component.navigation

local W = 50

local function cls() term.clear() term.setCursor(1,1) end
local function line(c) print(string.rep(c or "─", W)) end

local function header(title)
    cls() line("═")
    local pad = math.floor((W - #title - 2) / 2)
    print(string.rep(" ", pad) .. "[ " .. title .. " ]")
    line("═") print("")
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
    return io.read():lower() == "s"
end

local function pause()
    io.write("\nENTER para continuar...") io.read()
end

local TIMEOUT = 8

-- Toda comunicação vai para o drone, que repassa ao server se necessário
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
    return nil, "Sem resposta (timeout)"
end

local function listArmors()
    local r, e = request(P.MSG_LIST)
    if not r then return nil, e end
    if not r.ok then return nil, r.error end
    return r.armors
end

local function getPosition()
    local x, y, z = nav.getPosition()
    return math.floor(x), math.floor(y), math.floor(z)
end

local function showList(armors)
    if #armors == 0 then
        print("  (nenhuma armadura cadastrada)")
    else
        print(string.format("  %-4s %-20s %6s %6s %6s", "ID","NOME","X","Y","Z"))
        line()
        for _, a in ipairs(armors) do
            print(string.format("  %-4d %-20s %6d %6d %6d", a.id, a.name, a.x, a.y, a.z))
        end
    end
    print("")
end

local function screenAdd()
    header("ADICIONAR ARMADURA")
    local x, y, z = getPosition()
    print(string.format("  Posição atual: X=%d Y=%d Z=%d", x, y, z))
    print("")
    local name = prompt("  Nome: ")
    if name == "" then print("  Nome obrigatório.") pause() return end
    local px = tonumber(prompt("  X: ", x))
    local py = tonumber(prompt("  Y: ", y))
    local pz = tonumber(prompt("  Z: ", z))
    if not px or not py or not pz then print("  Coords inválidas.") pause() return end
    local r, e = request(P.MSG_ADD, { name=name, x=px, y=py, z=pz })
    if not r then print("  ERRO: "..tostring(e))
    elseif not r.ok then print("  ERRO: "..r.error)
    else print(string.format("\n  ✓ '%s' ID=%d", r.armor.name, r.armor.id)) end
    pause()
end

local function screenEdit(armors)
    header("EDITAR ARMADURA")
    showList(armors)
    local id = tonumber(prompt("  ID (0=cancelar): "))
    if not id or id == 0 then return end
    local r, e = request(P.MSG_GET, { id=id })
    if not r or not r.ok then print("  ERRO: "..tostring(e or r and r.error)) pause() return end
    local a = r.armor
    local x, y, z = getPosition()
    print(string.format("\n  Editando: %s | Sua pos: X=%d Y=%d Z=%d", a.name, x, y, z))
    local name = prompt("  Nome: ", a.name)
    local px = tonumber(prompt("  X: ", a.x))
    local py = tonumber(prompt("  Y: ", a.y))
    local pz = tonumber(prompt("  Z: ", a.z))
    local r2, e2 = request(P.MSG_EDIT, { id=id, name=name, x=px, y=py, z=pz })
    if not r2 then print("  ERRO: "..tostring(e2))
    elseif not r2.ok then print("  ERRO: "..r2.error)
    else print("  ✓ Atualizado.") end
    pause()
end

local function screenRemove(armors)
    header("REMOVER ARMADURA")
    showList(armors)
    local id = tonumber(prompt("  ID (0=cancelar): "))
    if not id or id == 0 then return end
    if not confirm("  Confirma?") then return end
    local r, e = request(P.MSG_REMOVE, { id=id })
    if not r then print("  ERRO: "..tostring(e))
    elseif not r.ok then print("  ERRO: "..r.error)
    else print("  ✓ Removida.") end
    pause()
end

local function screenSendMission(armors)
    header("ENVIAR MISSÃO AO DRONE")
    if #armors == 0 then print("  Nenhuma armadura.") pause() return end
    showList(armors)
    local id = tonumber(prompt("  ID da armadura (0=cancelar): "))
    if not id or id == 0 then return end
    local dx, dy, dz = getPosition()
    print(string.format("\n  Entrega em: X=%d Y=%d Z=%d", dx, dy, dz))
    if not confirm("  Enviar missão?") then return end

    -- Manda missão ao drone — ele busca as coords no server
    tunnel.send(serial.serialize({
        type = P.MSG_MISSION,
        data = { armor_id=id, dx=dx, dy=dy, dz=dz }
    }))

    print("\n  ✓ Missão enviada! Aguardando drone...")
    print("")

    local deadline = require("computer").uptime() + 120
    while require("computer").uptime() < deadline do
        local _, _, _, _, _, raw = event.pull(2, "modem_message")
        if raw then
            local ok, msg = pcall(serial.unserialize, raw)
            if ok and msg and msg.replyType and msg.replyType ~= P.MSG_REPLY then
                local icon = msg.replyType == P.MSG_OK and "✓" or
                             msg.replyType == P.MSG_ERROR and "✗" or "·"
                print("  " .. icon .. " " .. tostring(msg.text or ""))
                if msg.replyType == P.MSG_OK or msg.replyType == P.MSG_ERROR then break end
            end
        end
    end
    pause()
end

local function main()
    while true do
        local armors, err = listArmors()
        header("SISTEMA DE ARMADURAS")
        if not armors then
            print("  [!] Drone/Server offline: " .. tostring(err))
            print("") armors = {}
        else
            print("  Armaduras: " .. #armors) print("")
        end
        line()
        print("  1. Listar")
        print("  2. Adicionar")
        print("  3. Editar")
        print("  4. Remover")
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
        elseif op == "0" then cls() return end
    end
end

main()
