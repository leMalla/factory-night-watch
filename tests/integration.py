import json
import os
import shutil
import sys
import signal
import socket
import struct
import subprocess
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BASE_ONLY = '--base-only' in sys.argv[1:]
TEST = ROOT / 'build' / ('integration-base' if BASE_ONLY else 'integration')
GAME_PORT = 34998 if BASE_ONLY else 34997
RCON_PORT = 27996 if BASE_ONLY else 27995
ENGINE = os.environ.get('FACTORIO_BIN')
if not ENGINE:
    raise SystemExit('Set FACTORIO_BIN to the Factorio 2.1.23 headless executable.')
ENGINE = str(Path(ENGINE).expanduser().resolve())
TEST.mkdir(parents=True, exist_ok=True)
MODS = TEST / 'mods'
MODS.mkdir(exist_ok=True)
info = json.loads((ROOT/'mod/info.json').read_text())
source = MODS / (info['name']+'_'+info['version'])
shutil.copytree(ROOT/'mod', source, dirs_exist_ok=True)
bridge = (ROOT/'tests/engine-bridge.lua').read_text()
with (source/'control.lua').open('a') as f:
    f.write('\n'+bridge)
names = ['base', 'factory-night-watch'] if BASE_ONLY else ['base', 'elevated-rails', 'quality', 'recycler', 'space-age', 'factory-night-watch']
(MODS/'mod-list.json').write_text(json.dumps({'mods':[{'name':n,'enabled':True} for n in names]}))
data = Path(ENGINE).parents[2]/'data'
(TEST/'config.ini').write_text('[path]\nread-data='+str(data)+'\nwrite-data='+str(TEST)+'\n')
server_settings=json.loads((data/'server-settings.example.json').read_text())
server_settings.update({'name':'Night Watch integration test', 'description':'Local automated tests', 'visibility':{'public':False,'lan':False}, 'require_user_verification':False, 'auto_pause':False, 'autosave_interval':0, 'allow_commands':'true'})
(TEST/'server.json').write_text(json.dumps(server_settings))
proc = None
sock = None
logfile = None
request_id = 10
passed = []

def packet(ident, typ, body):
    payload = struct.pack('<ii', ident, typ) + body.encode() + b'\0\0'
    return struct.pack('<i', len(payload)) + payload

def read_packet():
    def read(n):
        result = b''
        while len(result) < n:
            chunk = sock.recv(n-len(result))
            if not chunk: raise RuntimeError('RCON disconnected')
            result += chunk
        return result
    size = struct.unpack('<i', read(4))[0]
    data = read(size)
    return (*struct.unpack('<ii', data[:8]), data[8:-2].decode())

def command(text):
    global request_id
    request_id += 2
    sock.sendall(packet(request_id, 2, text))
    sock.sendall(packet(request_id+1, 2, '/version'))
    output=[]
    while True:
        ident, typ, body = read_packet()
        if ident == request_id:
            if 'Error' in body or 'Cannot execute' in body:
                raise RuntimeError(body)
            output.append(body)
        elif ident == request_id+1:
            return ''.join(output)

def lua(code): return command('/silent-command ' + code)
def status():
    reply=lua('rcon.print(helpers.table_to_json(remote.call("factory-night-watch", "status")))')
    try:return json.loads(reply)
    except Exception:raise RuntimeError('Unexpected status reply: '+repr(reply))
def setting(name, value):
    command('/fnw-set ' + name + ' ' + (json.dumps(value) if not isinstance(value,str) else value))
def check(condition, label):
    assert condition, label
    passed.append(label)
    print('PASS:', label, flush=True)
def wait_alarm(timeout=15):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        s = status()
        if s.get('alarm'): return s
        time.sleep(.1)
    raise AssertionError('No protection pause before timeout: '+str(status()))

def start(save):
    global proc, sock, logfile
    logfile = (TEST / ('server-' + str(time.time_ns()) + '.log')).open('w')
    proc = subprocess.Popen([
        ENGINE, '--config', str(TEST/'config.ini'), '--mod-directory', str(MODS),
        '--start-server', str(save), '--server-settings', str(TEST/'server.json'),
        '--bind', f'127.0.0.1:{GAME_PORT}', '--rcon-bind', f'127.0.0.1:{RCON_PORT}',
        '--rcon-password', 'local-integration-test-only'
    ], stdin=subprocess.PIPE, stdout=logfile, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 30
    while time.monotonic() < deadline:
        if proc.poll() is not None: raise RuntimeError('Server died: '+str(logfile.name))
        try:
            sock = socket.create_connection(('127.0.0.1',RCON_PORT),timeout=1)
            break
        except OSError: time.sleep(.1)
    else: raise RuntimeError('Server startup timeout')
    sock.settimeout(10)
    sock.sendall(packet(1,3,'local-integration-test-only'))
    while True:
        ident,typ,body=read_packet()
        if typ==2:
            assert ident==1
            break

def stop():
    global proc,sock
    if sock: sock.close();sock=None
    if proc and proc.poll() is None:
        proc.send_signal(signal.SIGTERM)
        proc.wait(timeout=30)
    if logfile: logfile.close()

try:
    (TEST/'saves').mkdir(exist_ok=True)
    for path in (TEST/'saves').glob('factory-night-watch-emergency-*.zip'):
        path.unlink()
    subprocess.run([ENGINE, '--config', str(TEST/'config.ini'), '--mod-directory', str(MODS),
                    '--create', str(TEST/'test.zip')], check=True, stdout=subprocess.DEVNULL)
    start(TEST/'test.zip')
    lua('rcon.print("warmup")')
    setting('research-pause',False)
    check(status()['offline'] and not status()['paused'], 'offline factory runs')
    check('nauvis' in lua('rcon.print(game.surfaces.nauvis.planet and game.surfaces.nauvis.planet.name or "none")'), 'starting surface is a monitored real planet')
    command('/fnw-test-pause')
    check(status()['paused'] and status().get('alarm'), 'manual protection test latches pause')
    time.sleep(.5)
    saves=list((TEST/'saves').glob('factory-night-watch-emergency-*.zip'))
    check(bool(saves), 'emergency ZIP saved while paused')
    reload_save=max(saves,key=lambda p:p.stat().st_mtime_ns)
    stop();start(reload_save)
    check(status()['paused'] and status().get('alarm'), 'protection pause survives save/reload')
    command('/fnw-resume')
    check(not status()['paused'] and not status().get('alarm'), 'admin acknowledgement resumes')

    lua('game.speed=10')
    setting('max-offline-hours',.001)
    command('/fnw-resume')
    s=wait_alarm()
    check(s['alarm']['reason'][0]=='fnw-message.time-limit', 'configurable offline time limit triggers')
    setting('max-offline-hours',0)
    command('/fnw-resume')
    time.sleep(.5)
    check(not status()['paused'], 'zero disables offline time limit')

    setting('research-idle-minutes',.1)
    setting('research-pause',True)
    s=wait_alarm()
    check(s['alarm']['reason'][0]=='fnw-message.research', 'empty research queue pauses after delay')
    command('/fnw-resume')
    selected=lua('game.forces.player.technologies["automation-science-pack"].researched=true; game.forces.player.add_research("automation"); rcon.print(game.forces.player.current_research and game.forces.player.current_research.name or "none")')
    check('automation' in selected, 'test research was accepted by engine')
    time.sleep(1)
    check(not status()['paused'], 'selected research with no science does not trigger')
    lua('game.forces.player.cancel_current_research()')
    wait_alarm()
    check(status()['paused'], 'empty queue after cancellation triggers')
    setting('research-pause',False)
    command('/fnw-resume')

    # Exact building prototypes are excluded globally, independently of area rules.
    command('/fnw-it-exclusions {"names":["stone-furnace","wooden-chest","stone-furnace"]}')
    check(len(json.loads(command('/fnw-it-exclusions {"status":true}')))==2, 'real prototype list is validated and deduplicated')
    lua('game.surfaces.nauvis.create_entity{name="stone-furnace",position={-60,-60},force="player"}.die("enemy")')
    check(not status()['paused'], 'explicit furnace exclusion suppresses real destruction event')
    lua('game.surfaces.nauvis.create_entity{name="wooden-chest",position={-65,-65},force="player"}.die("enemy")')
    check(not status()['paused'], 'multiple building prototypes can be excluded together')
    lua('game.surfaces.nauvis.create_entity{name="iron-chest",position={-65,-65},force="player"}.die("enemy")')
    check(status()['paused'], 'another container prototype remains monitored')
    command('/fnw-resume');command('/fnw-it-exclusions {"names":[]}')
    lua('game.surfaces.nauvis.create_entity{name="stone-furnace",position={-60,-60},force="player"}.die("enemy")')
    check(status()['paused'], 'clearing prototype exclusions restores destruction alarms')
    command('/fnw-resume');command('/fnw-it-exclusions {"names":["wooden-chest"]}')

    # Persisted exclusions on real engine surfaces, with genuine destruction events.
    command('/fnw-it-areas '+json.dumps({'left':-40,'top':-40,'right':-20,'bottom':-20}))
    lua('game.surfaces.nauvis.create_entity{name="stone-furnace",position={-30,-30},force="player"}.die("enemy")')
    check(not status()['paused'], 'excluded furnace destruction does not alarm')
    check(command('/fnw-it-areas {"draw":true}').strip()=='true', 'real engine accepts rectangle highlight parameters')
    lua('game.surfaces.nauvis.create_entity{name="assembling-machine-1",position={-35,-35},force="player"}.die("enemy")')
    check(not status()['paused'], 'exclusion ignores another building type')
    lua('game.surfaces.nauvis.create_entity{name="stone-furnace",position={-40,-40},force="player"}.die("enemy")')
    check(not status()['paused'], 'top-left exclusion edge is included')
    lua('game.surfaces.nauvis.create_entity{name="stone-furnace",position={-20,-30},force="player"}.die("enemy")')
    check(status()['paused'], 'right exclusion edge remains monitored')
    command('/fnw-resume')
    lua('game.surfaces.nauvis.create_entity{name="stone-furnace",position={-30,-20},force="player"}.die("enemy")')
    check(status()['paused'], 'bottom exclusion edge remains monitored')
    command('/fnw-resume')
    command('/fnw-test-pause')
    region_save=max((TEST/'saves').glob('factory-night-watch-emergency-*.zip'),key=lambda p:p.stat().st_mtime_ns)
    stop();start(region_save);command('/fnw-resume')
    check(json.loads(command('/fnw-it-exclusions {"status":true}'))==['wooden-chest'], 'building exclusion list survives native save/reload')
    command('/fnw-it-exclusions {"names":[]}')
    areas=json.loads(command('/fnw-it-areas {"status":true}'))
    check(len(areas)==1 and areas[0]['left']==-40, 'exclusion geometry and surface survive actual save/reload')
    lua('game.surfaces.nauvis.create_entity{name="stone-furnace",position={-30,-30},force="player"}.die("enemy")')
    check(not status()['paused'], 'reloaded exclusion still suppresses structure-loss pause')
    lua('game.create_surface("area-test")')
    command('/fnw-it-areas '+json.dumps({'surface':'area-test','left':-40,'top':-40,'right':-20,'bottom':-20}))
    check(command('/fnw-it-areas {"probe":true,"surface":"area-test","x":-30,"y":-30}').strip()=='true', 'same coordinates on second surface can be excluded independently')
    lua('game.surfaces["area-test"].name="area-renamed"')
    check(command('/fnw-it-areas {"probe":true,"surface":"area-renamed","x":-30,"y":-30}').strip()=='true', 'surface rename preserves real exclusion binding')
    lua('game.delete_surface("area-renamed")')
    time.sleep(.3)
    lua('game.create_surface("area-renamed")')
    check(command('/fnw-it-areas {"probe":true,"surface":"area-renamed","x":-30,"y":-30}').strip()=='false', 'deleted surface exclusion does not apply to replacement with same name')
    command('/fnw-it-areas {"clear":true}')
    command('/fnw-it-areas '+json.dumps({'left':-40,'top':-40,'right':-20,'bottom':-20,'enabled':False}))
    lua('game.surfaces.nauvis.create_entity{name="stone-furnace",position={-30,-30},force="player"}.die("enemy")')
    check(status()['paused'], 'disabled exclusion restores real structure-loss pause')
    command('/fnw-resume');command('/fnw-it-areas {"clear":true}')

    # Real map entities with enemy-attributed death events.
    lua('local s=game.surfaces.nauvis; s.create_entity{name="stone-wall",position={0,0},force="player"}.die("enemy")')
    check(not status()['paused'], 'ignored wall destruction does not pause')
    lua('local s=game.surfaces.nauvis; s.create_entity{name="stone-furnace",position={5,0},force="player"}.die("enemy")')
    check(status()['paused'], 'enemy destruction of a built structure triggers')
    command('/fnw-resume')
    lua('game.surfaces.nauvis.create_entity{name="stone-furnace",position={10,0},force="player"}.destroy()')
    check(not status()['paused'], 'script removal is not a destruction alarm')
    lua('local s=game.create_surface("blueprint-sandbox-test"); s.create_entity{name="stone-furnace",position={0,0},force="player"}.die("enemy")')
    check(not status()['paused'], 'synthetic sandbox surface is excluded')
    lua('game.surfaces.nauvis.create_entity{name="stone-furnace",position={15,0},force="enemy"}.die("player")')
    check(not status()['paused'], 'enemy-owned entities are excluded')

    if not BASE_ONLY:
        lua('local p=game.forces.player.create_space_platform{name="Guard test",planet="nauvis",starter_pack="space-platform-starter-pack"}; p.apply_starter_pack(); rcon.print(p.surface.name)')
        lua('local p=game.forces.player.platforms[1]; p.hub.health=p.hub.max_health*.2; p.hub.damage(1,"enemy","physical")')
        check(not status()['paused'], 'hub health alone no longer pauses')
        setting('enabled',False)
        check(status()['paused'] and not status().get('alarm'), 'empty-server pause mode pauses without creating an alarm')
        setting('enabled',True)
        time.sleep(.1)
        check(not status()['paused'], 'protected mode resumes ordinary empty-server pause')
        lua('game.forces.player.platforms[1].surface.create_entity{name="gun-turret",position={1,1},force="player"}.die("neutral")')
        check(status()['paused'], 'platform structure loss without enemy attribution triggers')


    command('/fnw-resume')
    lua('game.speed=1; local s=game.surfaces.nauvis; local p=s.create_entity{name="small-electric-pole",position={30,0},force="player"}; local c=s.create_entity{name="constant-combinator",position={31,0},force="player"};p.get_wire_connector(defines.wire_connector_id.circuit_red,true).connect_to(c.get_wire_connector(defines.wire_connector_id.circuit_red,true)); p.get_wire_connector(defines.wire_connector_id.circuit_green,true).connect_to(c.get_wire_connector(defines.wire_connector_id.circuit_green,true)); c.get_or_create_control_behavior().get_section(1).set_slot(1,{value={type="virtual",name="signal-A",quality="normal"},min=50})')
    time.sleep(1.1)
    command('/fnw-it-areas '+json.dumps({'left':-1000,'top':-1000,'right':1000,'bottom':1000}))
    command('/fnw-it-exclusions {"names":["small-electric-pole"]}')
    command('/fnw-it-rule {"op":">","threshold":999,"count":32}')
    started_tick=int(lua('rcon.print(game.tick)'))
    lua('game.speed=60')
    deadline=time.monotonic()+60
    while time.monotonic()<deadline:
        if int(lua('rcon.print(game.tick)'))-started_tick>=18000:
            break
        time.sleep(.2)
    else:
        raise AssertionError('32-rule soak did not advance five simulation minutes; ticks advanced='+str(int(lua('rcon.print(game.tick)'))-started_tick))
    current=status()
    check(not current['paused'] and len(current['circuits'])==32 and all(r.get('value')==50 for r in current['circuits']), '32 active circuit rules run for five simulation minutes without false pause')
    command('/fnw-it-rule {"clear":true}')
    lua('game.speed=1')
    reply=command('/fnw-it-rule {"op":"<","threshold":100,"delay":3,"signal":{"type":"virtual","name":"signal-A","quality":"normal"}}')
    check('COPIED' in reply, 'real engine copies circuit signals without table.deepcopy and preserves entity references')
    time.sleep(1.2)
    check(not status()['paused'] and status()['circuits'][0]['value']==50, 'real red circuit value is read while waiting')
    lua('game.surfaces.nauvis.find_entities_filtered{type="constant-combinator"}[1].get_control_behavior().get_section(1).set_slot(1,{value={type="virtual",name="signal-A",quality="normal"},min=150})')
    time.sleep(1.2)
    check(not status()['paused'] and not status()['circuits'][0]['match'] and 'since' not in status()['circuits'][0], 'false condition resets continuous delay')
    lua('game.surfaces.nauvis.find_entities_filtered{type="constant-combinator"}[1].get_control_behavior().get_section(1).set_slot(1,{value={type="virtual",name="signal-A",quality="normal"},min=50})')
    s=wait_alarm(12)
    check(s['alarm']['reason'][0]=='fnw-message.circuit', 'continuous circuit condition triggers safety pause')
    lua('game.surfaces.nauvis.find_entities_filtered{type="constant-combinator"}[1].get_control_behavior().enabled=false')
    time.sleep(.1)
    check(status()['paused'], 'signal clearing does not release safety latch')
    command('/fnw-it-rule {"clear":true}');command('/fnw-resume')
    for op,threshold in [('=',0),('≠',1),('≤',0),('≥',0),('>',-1)]:
        command('/fnw-it-rule '+json.dumps({'op':op,'threshold':threshold,'wire':2}))
        s=wait_alarm(3)
        check(s['alarm']['reason'][0]=='fnw-message.circuit','green circuit comparison '+op+' works')
        command('/fnw-it-rule {"clear":true}');command('/fnw-resume')
    command('/fnw-it-rule {"op":">","threshold":999}')
    lua('game.surfaces.nauvis.find_entities_filtered{type="electric-pole"}[1].get_wire_connector(defines.wire_connector_id.circuit_red,false).disconnect_all()')
    s=wait_alarm(3)
    check(s['alarm']['reason'][0]=='fnw-message.circuit-lost', 'lost red cable triggers fail-safe pause')
    command('/fnw-it-rule {"clear":true}');command('/fnw-resume')
    command('/fnw-it-rule {"wire":2,"op":">","threshold":999}')
    expected_position=json.loads(lua('rcon.print(helpers.table_to_json(game.surfaces.nauvis.find_entities_filtered{type="electric-pole"}[1].position))'))
    lua('game.surfaces.nauvis.find_entities_filtered{type="electric-pole"}[1].destroy()')
    s=wait_alarm(3)
    check(s['alarm']['reason'][0]=='fnw-message.circuit-lost', 'removed pole triggers fail-safe pause')
    check(s['alarm'].get('place',{}).get('x')==expected_position['x'] and s['alarm']['place']['y']==expected_position['y'], 'alarm keeps source coordinates after the pole is removed')
    time.sleep(.4)
    saved=max((TEST/'saves').glob('factory-night-watch-emergency-*.zip'),key=lambda p:p.stat().st_mtime_ns)
    stop();start(saved)
    check(status()['paused'] and status()['circuits'][0]['name']=='Engine circuit', 'circuit registry and safety latch survive save/reload')
    command('/fnw-it-rule {"clear":true}');command('/fnw-resume')
    ids=json.loads(lua('local s=game.surfaces.nauvis; local a=s.create_entity{name="constant-combinator",position={40,0},force="player"}; local b=s.create_entity{name="constant-combinator",position={40,3},force="player"}; a.get_or_create_control_behavior().get_section(1).set_slot(1,{value={type="virtual",name="signal-A",quality="normal"},min=50}); b.get_or_create_control_behavior().get_section(1).set_slot(1,{value={type="virtual",name="signal-A",quality="normal"},min=200}); local box=s.create_entity{name="steel-chest",position={42,0},force="player"}; local ins=s.create_entity{name="inserter",position={43,0},force="player"}; local comb=s.create_entity{name="arithmetic-combinator",position={44,0},force="player"}; local function link(x,i,y,j) x.get_wire_connector(i,true).connect_to(y.get_wire_connector(j,true)) end; local d=defines.wire_connector_id; link(a,d.circuit_red,box,d.circuit_red); link(box,d.circuit_red,ins,d.circuit_red); link(box,d.circuit_red,comb,d.combinator_input_red); link(a,d.circuit_green,comb,d.combinator_input_green); link(b,d.circuit_red,comb,d.combinator_output_red); link(b,d.circuit_green,comb,d.combinator_output_green); local p=s.create_entity{name="small-electric-pole",position={60,0},force="player"}; local q=s.create_entity{name="small-electric-pole",position={62,0},force="player"};link(p,d.pole_copper,q,d.pole_copper);local empty=s.create_entity{name="wooden-chest",position={80,0},force="player"};rcon.print(helpers.table_to_json({box=box.unit_number,inserter=ins.unit_number,combinator=comb.unit_number,power=p.unit_number,empty=empty.unit_number,input=d.combinator_input_red,output=d.combinator_output_red}))'))
    time.sleep(1.1)
    def networks(*units):
        return json.loads(command('/fnw-it-networks '+json.dumps({'entities':list(units)})))['options']
    box_options=networks(ids['box'])
    check(len(box_options)==1 and box_options[0].get('value')==50, 'real chest circuit can be selected and read without an electric pole: '+repr(box_options))
    check(len(networks(ids['box'],ids['inserter']))==1, 'real box-to-inserter network is deduplicated during area selection')
    four=networks(ids['combinator'])
    check(len(four)==4 and len({(r['wire'],r['id']) for r in four})==4, 'real combinator exposes four distinct input/output red/green networks')
    check(sorted(r['value'] for r in four)==[50,50,200,200], 'combinator input and output network values stay separate')
    check(len(networks(ids['box'],ids['inserter'],ids['combinator']))==4, 'mixed real entity selection deduplicates networks without losing output ports')
    check(len(networks(ids['power']))==0 and len(networks(ids['empty']))==0, 'copper-only and unwired real entities produce no circuit choices')
    command('/fnw-it-rule '+json.dumps({'unit':ids['inserter'],'op':'>','threshold':999}))
    time.sleep(1.1)
    check(not status()['paused'] and status()['circuits'][0]['value']==50, 'real inserter source is monitored without a pole')
    command('/fnw-it-rule {"clear":true}')
    command('/fnw-it-rule '+json.dumps({'unit':ids['combinator'],'connector':ids['input'],'op':'>','threshold':150}))
    time.sleep(1.1)
    check(not status()['paused'] and status()['circuits'][0]['value']==50, 'selected input never reads the larger output value')
    command('/fnw-it-rule {"clear":true}')
    command('/fnw-it-rule '+json.dumps({'unit':ids['combinator'],'connector':ids['output'],'op':'>','threshold':150}))
    s=wait_alarm(3)
    check(s['alarm']['reason'][0]=='fnw-message.circuit' and s['circuits'][0]['value']==200, 'exact output connector drives the safety pause')
    time.sleep(.4)
    output_save=max((TEST/'saves').glob('factory-night-watch-emergency-*.zip'),key=lambda p:p.stat().st_mtime_ns)
    stop();start(output_save);command('/fnw-resume')
    s=wait_alarm(3)
    check(s['circuits'][0]['value']==200, 'selected output connector survives save/reload and still triggers correctly')
    stop()
    (TEST/'RESULTS.json').write_text(json.dumps(passed,indent=2))
    print(f'ALL {len(passed)} INTEGRATION CHECKS PASSED')
finally:
    stop()
