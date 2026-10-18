import sys,struct,pathlib,json,hashlib
for filename in sys.argv[1:]:
 blob=pathlib.Path(filename).read_bytes()
 count=struct.unpack_from('<I',blob)[0]
 offsets=[(count+1)*4]+list(struct.unpack_from('<%dI'%count,blob,4))+[len(blob)]
 result={'path':filename,'size':len(blob),'sha256':hashlib.sha256(blob).hexdigest(),'contexts':count,'sections':[]}
 for section in range(count+1):
  offset=offsets[section]
  magic,extra,version,reservations,payload=struct.unpack_from('<5I',blob,offset)
  current_space=0;chunks=[]
  for index in range(reservations):
   value=struct.unpack_from('<I',blob,offset+20+index*4)[0]
   chunks.append({'space':current_space,'bytes':value&0x7fffffff})
   if value>>31:current_space+=1
  result['sections'].append({'section':section,'offset':offset,'magic':hex(magic),'external_refs':magic^0xc0de0000,'extra_refs':extra,'version_hash':hex(version),'payload':payload,'reservations':chunks,'code_chunks_fit_16k':all(c['bytes']<=475136 for c in chunks if c['space']==2)})
 print(json.dumps(result,indent=2))
