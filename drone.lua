local function proxy(n)
    local a=component.list(n)() return a and component.proxy(a) or nil
end

local function escape(s)
    s=tostring(s)
    s=s:gsub('\\','\\\\') s=s:gsub('"','\\"')
    s=s:gsub('\n','\\n')  s=s:gsub('\r','\\r')
    s=s:gsub('\0','\\0')
    return '"'..s..'"'
end

local function serialize(v)
    local t=type(v)
    if t=="nil" then return "nil"
    elseif t=="boolean" or t=="number" then return tostring(v)
    elseif t=="string" then return escape(v)
    elseif t=="table" then
        local s="{"
        for k,val in pairs(v) do
            local ks=type(k)=="string" and "["..escape(k).."]" or "["..tostring(k).."]"
            s=s..ks.."="..serialize(val)..","
        end
        return s.."}"
    end
    return "nil"
end

local function unserialize(s)
    if not s or s=="" then return nil end
    local ok,r=pcall(load("return "..s)) return ok and r or nil
end

local P={
    MSG_LIST="LIST",MSG_ADD="ADD",MSG_EDIT="EDIT",
    MSG_REMOVE="REMOVE",MSG_GET="GET",MSG_MISSION="MISSION",
    MSG_OK="OK",MSG_ERROR="ERROR",MSG_LOG="LOG",MSG_REPLY="REPLY",
    WAYPOINT_BASE="base"
}

-- Estado persistente na EEPROM data
-- Salva a missao e a etapa atual para sobreviver ao reinicio pos-teleporte
local eeprom=proxy("eeprom")

local function saveState(state)
    if eeprom then eeprom.setData(serialize(state)) end
end

local function loadState()
    if not eeprom then return nil end
    local raw=eeprom.getData()
    if not raw or raw=="" or raw:sub(1,1)~="{" then return nil end
    return unserialize(raw)
end

local function clearState()
    if eeprom then eeprom.setData("") end
end

local dis=proxy("dislocator_advanced")
if not dis then error("Sem dislocator!") end

local tunnels={}
for a,_ in component.list("tunnel") do
    tunnels[#tunnels+1]=component.proxy(a)
end
if #tunnels<2 then error("Precisa 2 tunnels! Tem:"..#tunnels) end

local tT,tS
local function identifyTunnels()
    for _,t in ipairs(tunnels) do
        t.send(serialize({type="PING",data={}}))
        local deadline=computer.uptime()+2
        while computer.uptime()<deadline do
            local ev,_,_,_,_,raw=computer.pullSignal(0.5)
            if ev=="modem_message" and raw then
                local r=unserialize(raw)
                if r and r.role=="server" then
                    tS=t break
                end
            end
        end
        if tS then break end
    end
    if tS then
        tT=tunnels[1]==tS and tunnels[2] or tunnels[1]
    else
        if tunnels[1].getChannel()<tunnels[2].getChannel() then
            tT,tS=tunnels[1],tunnels[2]
        else
            tT,tS=tunnels[2],tunnels[1]
        end
    end
end
identifyTunnels()

local function log(txt,tp)
    tp=tp or P.MSG_LOG
    tT.send(serialize({replyType=tp,text=tostring(txt)}))
end

local function relay(tp,data)
    tS.send(serialize({type=tp,data=data or {}}))
    local dl=computer.uptime()+5
    while computer.uptime()<dl do
        local ev,_,_,_,_,raw=computer.pullSignal(1)
        if ev=="modem_message" and raw then
            local r=unserialize(raw)
            if r and r.replyType==P.MSG_REPLY then return r end
        end
    end
    return nil,"timeout"
end

local function tpTo(name)
    local ts=dis.getTargets()
    for i,t in ipairs(ts) do
        if t.name==name then
            dis.setSelected(i-1)
            local ok,r=dis.activate()
            return ok,(ok and nil or tostring(r))
        end
    end
    return false,"waypoint nao encontrado: "..name
end

local SLOT=0
local function tpCoords(x,y,z,lbl)
    local ts=dis.getTargets()
    if #ts==0 then dis.addTarget(x,y,z,0,lbl)
    else dis.setTarget(SLOT,x,y,z,0,lbl) end
    dis.setSelected(SLOT)
    local ok,r=dis.activate()
    return ok,(ok and nil or tostring(r))
end

local collect={}
collect[1]=function()
    log("[placeholder] Coletando 1...")
    local d=computer.uptime()+1
    while computer.uptime()<d do computer.pullSignal(0.1) end
    return true
end
collect[2]=function()
    log("[placeholder] Coletando 2...")
    local d=computer.uptime()+1
    while computer.uptime()<d do computer.pullSignal(0.1) end
    return true
end

local function deliver()
    log("[placeholder] Entregando...")
    local d=computer.uptime()+1
    while computer.uptime()<d do computer.pullSignal(0.1) end
    return true
end

-- Etapas da missao:
-- 1 = indo buscar armadura
-- 2 = coletando
-- 3 = indo entregar
-- 4 = entregando
-- 5 = voltando para base
local function mission(data,startStep)
    startStep=startStep or 1
    local id=data.armor_id

    -- Busca dados da armadura se ainda nao temos
    local arm=data.armor
    if not arm then
        local r,e=relay(P.MSG_GET,{id=id})
        if not r or not r.ok then
            log("Erro server:"..(e or r and r.error or "?"),P.MSG_ERROR)
            clearState() return
        end
        arm=r.armor
        data.armor=arm
    end

    if startStep<=1 then
        log("Indo buscar "..arm.name)
        saveState({step=1,data=data})
        local ok,er=tpCoords(arm.x,arm.y,arm.z,"_a")
        if not ok then log("Falha tp:"..tostring(er),P.MSG_ERROR) clearState() return end
    end

    if startStep<=2 then
        log("Chegou. Coletando...")
        saveState({step=2,data=data})
        local fn=collect[id]
        if not fn then log("Sem coleta id="..id,P.MSG_ERROR) clearState() return end
        fn()
    end

    if startStep<=3 then
        log("Indo entregar")
        saveState({step=3,data=data})
        local ok,er=tpCoords(data.dx,data.dy,data.dz,"_d")
        if not ok then log("Falha tp:"..tostring(er),P.MSG_ERROR) clearState() return end
    end

    if startStep<=4 then
        log("Entregando...")
        saveState({step=4,data=data})
        deliver()
    end

    if startStep<=5 then
        log("Voltando para base...")
        saveState({step=5,data=data})
        local ok,er=tpTo(P.WAYPOINT_BASE)
        if not ok then log("Falha base:"..tostring(er),P.MSG_ERROR) clearState() return end
    end

    clearState()
    log("Missao concluida!",P.MSG_OK)
end

log("Drone OK")

-- Verifica se ha missao em andamento (reinicio pos-teleporte)
local state=loadState()
if state and state.step and state.data then
    log("Retomando missao na etapa "..state.step)
    pcall(mission,state.data,state.step+1)
end

while true do
    local ev,_,_,_,_,raw=computer.pullSignal(1)
    if ev=="modem_message" and raw then
        local msg=unserialize(raw)
        if msg then
            if msg.type==P.MSG_MISSION then
                pcall(mission,msg.data or {})
            elseif msg.type then
                local rsp,er=relay(msg.type,msg.data)
                if not rsp then rsp={ok=false,error=tostring(er)} end
                rsp.replyType=P.MSG_REPLY
                tT.send(serialize(rsp))
            end
        end
    end
end
