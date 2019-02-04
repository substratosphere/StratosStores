--[[ StratosStores ]]--
--[[
	Roblox Datastores management system.
	Developed by substratosphere on Roblox.
	--Visit @subphere on Twitter.
	
	**THIS CODE HAS NOT YET BEEN TESTED AFTER IT WAS PORTED TO A SEPERATE MODULE - USE AT OWN RISK**
	**THIS REQUIRES COMPETENT CODING KNOWLEDGE TO INTEGRATE INTO YOUR GAME**
	**PLEASE READ ALL INFORMATION PROVIDED IN THIS MODULE**
	**THIS IS ONLY SERVER SIDE CODE FOR STATOSSTORES**
	
	Part of the Atmosphere Framework, this has been converted to a module and open sourced under 
	
	--	GNU General Public License v3.0	--
	Permissions of this strong copyleft license are conditioned on making available complete source code 
	of licensed works and modifications, which include larger works using a licensed work, under the same 
	license. Copyright and license notices must be preserved. Contributors provide an express grant of 
	patent rights.
	
	Features:
		i) Prevents datastore throttling.
		ii) Ensures reliable data saving.
		iii) Minimal data transfer between client & server.
		iv) Periodic autosaving from queue.
		v) Save verification api. Ensures saves save before updating the local data. If the save fails an error is returne
		   and the player data is not updated with the changes requested.
			--All data is read as old data even with value changes until save is verified as success.
		vi) Loads temporary data for players that does not save if DataStores fail or are corrpupted
]]

local OBSCURE="ABCD" --Obscures the Roblox DataStore key helping prevent exploiters adjusting saves.

local api={}
local DataStores=game:GetService("DataStoreService")
local Marketplace=game:GetService("MarketplaceService")
local isSaving={}
local data={}
local savequeue={}
api.players={}

local function dataStore(n,scope)
	return DataStores:GetDataStore(n,scope)
end

local Data={}
for i,v in pairs {
	--DataStores Available
	--Security [Bool][required]: If enabled it prevents the client saving to it
	--OnLoad [Function]: Runs when the data first loads. Use for verifying & updating variables if necessary.
	DS1={security=false},
	DS2={security=true}
	
} do
	Data[i].ds=dataStore(i)
end


--------------------------------------------------------------------------------------------------------

--[[ Documentation ]]--
--[[
	>> CreateKeys <<
	--Creates keys to send to the client to update their local data state. These should be stored in an
	  array and sent to the client whenever a save is updated.
		--If using >>SafeSave<< this should be the value returned (see below).
	
	>>SafeSave<<
	--You must return keys
	--s tells you whether it was a success
	--ClientKeys are the keys created to update the client, which should be sent over.
	
	local s,ClientKeys=api.SafeSave("DS1",p,function(DS,Keys,Data) --DataStore Name, Player Object, Data Update
	
		Data.Currency.Credits=Data.Currency.Credits+1000 --Adjust all the values you want changed here.
			
		return {
			api.CreateKeys(DS,Data.Currency.Credits,"Currency","Credits")
			
			--Requires the value you changed & each key to the value as strings.
				--This is whats sent to the client.
		}
	end)
	
	
	>> ClientSave <<
	--If a DataStore has security disabled the client can request a save to it. Do not use this if saving
	  from the server.
	
	>> ServerSave <<
	--The standard DataStore saving function. Do not use this if requesting a save from the client.
	
	>> SaveQueued <<
	--Used for saving all the data that's in the save queue. Recommended to call at least once per
	  minute.
	
	>> PlayerJoined <<
	--Must be fired when the player joins.
	
	>> PlayerRemoving <<
	--Must be fired when the player leaves.
]]

--------------------------------------------------------------------------------------------------------


--[[ Deep Copy ]]--
--Deep copies a table.
local function CopyTable(o)
	local copy={}
	for i,v in pairs(o) do
		copy[i]=(type(v)=="table" and CopyTable(v)) or v
	end
	return copy
end

--[[ Table Count ]]--
--Returns the size of a table
local function TableCount(tab)
	if (next(tab) and #tab<1) then
		local count=0
		for _ in pairs (tab) do
			count=count+1
		end
		return count
	else
		return #tab
	end
end

--[[ Key Exists ]]--
--Checks the key exists.
local function KeyExists(tab,keys)
	local n=#keys>1
	n=(n and #keys) or 1
	if (n>1) then
		for i=1,n-1 do
			tab=tab[keys[i]]
			if not (tab) then
				print("Provided keys do not exist.")
				return
			end
		end
	end
	if (tab) then
		return tab,keys[n]
	end
end

--[[ Half Match ]]--
--Adds missing indexes to table.
local function HalfMatch(n,o) --To match,loaded
	o=o or {}
	for i,v in pairs (n) do
		if (type(v)=="table") then
			o[i]=halfMatch(v,o[i])
		elseif (o[i]==nil) then
			o[i]=v
		end
	end
	return o
end

--[[ Real Save ]]--
--Saving function to Roblox Datastores.
function api.ServerSave(s,key,data,tab)
	--[[
		s   		- The datastore name to save/load/update from
		key 		- The key to save/load/update from
		data		- The data to be saved
			tab={
				bypass, 	- Prevents the data being saved to the queue if it fails.
				key, 		- A priority key for use with throttling.
			}
	]]
	
	local update=type(data)=="function" and data
	data=not update and data --Sets the data to nil if it is the update
	
	local actionType=(update and "update") or (data and "save") or "load"
	
	--Checks to ensure all the required parameters exist
	if not (s) then
		print("Could not",actionType,"data. No store provided.")
		return
	elseif not (key) then
		print("Could not",actionType,"data. No key provided.")
		return
	end
	
	--Loads the datastore to save to
	local store=Data[s]
	store=store and store.ds
	if not (store) then
		print("Could not",actionType,"data, store",s,"does not exist.")
		return
	end
	
	--Check for NAN fields!
	local function cycle(tab)
		for i,v in pairs (tab) do
			if (type(v)=="table") then
				cycle(v)
			elseif not (v==v) then
				warn(key,"has corrupt data! NAN fields detected!")
				return true
			end
		end
	end
	if (data) and (cycle(data)) then
		return
	end
	
	
	--Loads the players data
	local lastSave=tonumber(key) and api.players[game.Players:GetPlayerByUserId(tab and tab.key or key)]
	if (data) or (update) then --If saving/updating
		if (lastSave) then
			if not (lastSave.canSave) then --Rejects the save if canSave is false!
				print("Save rejected. Player is using temporary data.")
				return
			end
		end
		if (isSaving[key]) then --Sets that it is currently saving.
			isSaving[key][s]=true
		end
	end
	
	--Forces a delay to prevent throttling
	lastSave=lastSave and lastSave.dataLast
	if (lastSave) then
		wait(math.clamp(6-(tick()-lastSave[s]),0,6))
	end
	
	--Set saving status
	if (isSaving[key]) then
		if (isSaving[key].disabled) and not (tab.leaving) then
			warn("Saving is disabled!")
			return
		elseif (data) or (update) then
			isSaving[key][s]=true
		end
	end
	
	--Datastore saving/loading function
	local function sync()
		local key=tostring(key)..OBSCURE --Obscures the key.
		if (update) then
			local ret
			store:UpdateAsync(key,function(data)
				local newData=update(data)
				ret=newData or data
				return newData
			end)
			return ret
		elseif (data) then
			store:SetAsync(key,data)
			return data
		else
			return store:GetAsync(key)
		end
	end
	
	local attempt,worked,dataLoad=0,false
	local tl=4
	repeat
		worked,dataLoad=pcall(sync)
		if not (worked) then
			print("Datastores",actionType,"error ("..dataLoad..")")
			wait(tl)
			tl=tl*2
		end
		attempt=attempt+1
	until worked or attempt>=3
	
	if (worked) and (lastSave) then --Sets the last save time if it worked
		lastSave[s]=tick()
	elseif not (worked) and (tab) and not (tab.bypass) and (data) then --Queues the requested save if failed
		savequeue[key]=savequeue[key] or {}
		table.insert(savequeue,{stores=s,data=data})
	end
	
	if (data) or (update) and (isSaving[key]) then --Sets the saving key to false
		isSaving[key][s]=nil
	end
	
	if (dataLoad) and (cycle(dataLoad)) then
		return false
	end
	
	return worked,dataLoad
end

--[[ Save Queued Data ]]--
--Saves all the data stored in the queue (recommended to run periodically).
function api.SaveQueued()
	for i,v in pairs (savequeue) do
		savequeue[i]=nil
		for s,v in pairs (v) do
			if (s) and (i) and not (v==nil) then
				coroutine.resume(coroutine.create(function()
					local w=api.ServerSave(s,i,v)
					if not (w) then
						print("Autosave failed for ",i,"!")
					end
				end))
			else
				warn("Error Saving Queued. | Stores",not s==nil,"| Key",not i==nil,"| Data",not v==nil)
			end
		end
	end
end

--[[ Save Data ]]--
--All client calls should go through this.
function api.ClientSave(p,t,data)
	if not (data) or not (type(data)=="table") then
		print(p,"requested data save but didn't provide data formatted correctly!")
		return
	end
	if (isSaving[p.UserId].disabled) then --Reject all save requests from the client.
		return
	end
	local keys=data.keys
	local val=data.value
	if not (keys) then
		print(p,"requested data save but didn't provide any keys!")
		return
	end
	local serverData=api.players[p]
	
	if not (serverData.canSave) then
		print(p,"requested data save but canSave is disabled.")
		return
	end
	
	local function addQueue(serverData,tab,n)
		if (tab) then
			if (tab[n]==val) then return true end
			tab[n]=val
			local id=p.UserId
			savequeue[id]=savequeue[id] or {}
			savequeue[id][t]=serverData --Definitely ensures latest to save.
			return true
		else
			print(p,"requested data save but",unpack(keys),"doesn't exist.")
		end
	end
	
	for i,v in pairs (Data) do
		if (string.lower(t)==string.lower(i)) then
			if not (v.security) then
				local data=serverData.data[i]
				if (data) and (data.ds) then
					return addQueue(data.ds,KeyExists(data.ds,keys))
				end
			else
				--[[
					if (v=="DS1") then
						--Add exceptions here for datastores with security enabled.
						--Eg,
						--   You could use this to allow the client to request save
						     to only certain variables in the DataStore.
					end
				--]]
			end
			break
		end
	end
	print(p,"requested data save but the DataStore did not exist.")
end

--[[ Safe Save ]]-- *Do Not Use With Client - Server-Side Saves ONLY*
--Ensures that the data saves succesfully, otherwise it returns an error.
function api.SafeSave(DS,p,func)
	local p2=api.players[p]
	if (p2) then
		if not (p2.canSave) then
			print(p,"requested save but canSave is set to false!")
			return
		end
		local uid,data=p.UserId,p2.data
		if (uid) and (data) then
			local capture=CopyTable(data)
			local tab=func(DS,uid,capture) --Keys
			if (api.ServerSave(DS,uid,data[DS],{bypass=true})) then
				p2.data=data
				return unpack(tab)
			else
				p2.data=capture
				warn("Save not verified.")
			end
		else
			print(p,"requested save but could not fetch data!")
		end
	else
		print(p,"requested save but not added to network!")
	end
end

--[[ Key Creator ]]--
--Creates a table with keys stored for updating the client.
function api.CreateKeys(t,val,...)
	return {t=t,keys={...},value=val}
end

--[[ Player Added ]]--
--Initiates and loads system for player.
function api.PlayerAdded(p)
	local pName,pID=p.Name,p.UserId
	local canSave=true
	local dataLast,dataLoad={},{}
	
	local function loadData(n,tab,f)
		local tab,isDefault=CopyTable(tab),true
		local s,data=api.ServerSave(n,pID,function(data)
			isDefault=data==nil
			data=HalfMatch(tab,data) or tab
			local update=f and f(data,tab) --Loaded, Default
			return update or data
		end)
		if not (s) then
			warn("Failed to sync "..pName.."'s",n,"data, any data will not be saved to datastores!")
		end
		canSave=(s and canSave) or false
		print(pName.."'s",n,"data",(not isDefault and "loaded from datastores") or "loaded from default module")
		dataLast[n]=tick()
		dataLoad[n]=(s and type(data)=="table" and data) or tab
	end
	
	for i,v in pairs (Data) do
		local module=script:FindFirstChild(i)
		if (module) then
			loadData(i,require(module),v.OnLoad)
		end
	end
	
	api.players[p]={dataLast=dataLast,data=dataLoad,canSave=canSave}
	warn(dataLoad.canSave and "Can" or "Can't","save",pName.."'s data.")
end	

--[[ Player Removed ]]--
--Saves everything in the queue if allowed.
function api.PlayerRemoved(p)
	local data=api.players[p]
	local id,name=p.UserId,p.Name
	isSaving[id].disabled=true --Notifies that all save requests are to be rejected.
	if (data) and (data.canSave) then --Dont need to save anything in the queue because variables have been locally updated.
		local queuedData=savequeue[id] or {}
		
		for i,v in pairs (Data) do
			isSaving[id][i]=nil
			if not (v.security) then
				queuedData[i]=data.data[i] --Definitely ensures latest to save.
			end
		end
		
		if (queuedData) then
			for i,v in pairs (queuedData) do
				if (i) and (v) then
					data.dataLast[i]=tick()-7 --Will force it to save regardless of throttling.
					local w=api.ServerSave(i,id,v,{leaving=true})
					if not (w) then
						print("Save on leave ("..i..") failed for",name.."!")
					end
				end
			end
			warn("Saved "..name.."'s data on leave.")
		end
		
		while (TableCount(isSaving[id])>1) do
			wait(1) --Is data was already saving via alt. method, it waits for it to save!
		end
	else
		print("Can not save players data because",(not data and "data was not found") or "canSave is disabled.")
	end
	isSaving[id]=nil --Wipes all isSaving properties for api client.
	api.players[p]=nil --Wipes player from atmosphere network.
end

--[[ On Close ]]--
--Ensures all save data in the queue saves before game is close.
game:BindToClose(function()
	print("Closing Network...")
	wait(1)
	while (next(isSaving)) do
		wait(1)
	end
	print("Network closed.")
end)
