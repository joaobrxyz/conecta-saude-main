// Run after `mvn verify` in each service and `npm ci` in frontend.
// Uses disposable databases in the existing local Docker database containers.
import { spawn, spawnSync } from 'node:child_process';
import { randomBytes } from 'node:crypto';
import { createServer } from 'node:net';
import { openSync, closeSync, writeFileSync, unlinkSync, existsSync } from 'node:fs';
import { resolve, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { tmpdir } from 'node:os';
import assert from 'node:assert/strict';

const root = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const javaSettings = spawnSync('java', ['-XshowSettings:properties', '-version'], { encoding: 'utf8', windowsHide: true });
const javaHome = javaSettings.stderr?.match(/java.home\s*=\s*(.+)/)?.[1].trim();
if (!javaHome) throw new Error('Java is not available.');
const javaExecutable = resolve(javaHome, 'bin', process.platform === 'win32' ? 'java.exe' : 'java');
const suffix = `${Date.now()}_${randomBytes(3).toString('hex')}`;
const database = `integration_${suffix}`;
const password = randomBytes(24).toString('base64url');
const secret = randomBytes(32).toString('base64url');
const email = 'admin@integration.example';
const ports = { gateway: 18080, appointment: 18081, identity: 18082, clinical: 18083, frontend: 14200 };
const children = [];
const created = [];
const proxyPath = resolve(tmpdir(), `conecta-proxy-${suffix}.json`);
const base = `http://127.0.0.1:${ports.frontend}/api`;
let assertions = 0;

function docker(...args) {
  const result = spawnSync('docker', args, { encoding: 'utf8', windowsHide: true });
  if (result.status !== 0) throw new Error(result.stderr || 'Docker command failed');
  return result.stdout;
}
async function free(port) {
  await new Promise((resolve, reject) => { const server = createServer(); server.once('error', reject); server.listen(port, '127.0.0.1', () => server.close(resolve)); });
}
function launch(name, command, args, cwd = root) {
  const logPath = resolve(root, `.integration-${name}.runtime.log`);
  const log = openSync(logPath, 'w');
  const child = spawn(command, args, { cwd, windowsHide: true, stdio: ['ignore', log, log] });
  closeSync(log); children.push(child);
  child.on('error', error => console.error(`${name}: ${error.message}`));
  return child;
}
async function ready(url) {
  const deadline = Date.now() + 180_000;
  while (Date.now() < deadline) {
    if (children.some(child => child.exitCode !== null)) throw new Error('A service exited; inspect .integration-*.runtime.log');
    try { const response = await fetch(url, { signal: AbortSignal.timeout(3000) }); if (response.status < 500) return; } catch {}
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  throw new Error(`Service did not become ready: ${url}`);
}
async function request(path, { token, method = 'GET', body, status = 200, contentType = 'application/json' } = {}) {
  const response = await fetch(base + path, { method, headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body !== undefined ? { 'Content-Type': contentType } : {}) }, body: body === undefined ? undefined : contentType === 'application/json' ? JSON.stringify(body) : body });
  const text = await response.text();
  assert.equal(response.status, status, `${method} ${path}: ${response.status} ${text}`); assertions++;
  return text ? JSON.parse(text) : null;
}
async function login(email) { return request('/auth/login', { method: 'POST', body: { email, senha: password, manterConectado: false } }); }
function cpf(seed) {
  const digits = seed.split('').map(Number);
  for (const size of [9, 10]) { const mod = (digits.reduce((sum, digit, i) => sum + digit * (size + 1 - i), 0) * 10) % 11; digits.push(mod === 10 ? 0 : mod); }
  return digits.join('');
}

try {
  for (const port of Object.values(ports)) await free(port);
  for (const [container, existing] of [['identity_postgres_v2', 'db_identity'], ['appointment_postgres', 'appointment_db']]) {
    docker('exec', container, 'psql', '-U', 'admin', '-d', existing, '-c', `CREATE DATABASE ${database}`);
    created.push([container, existing]);
  }
  const launchJava = (name, service, args) => {
    const jar = resolve(root, service, 'target', `${service}-0.0.1-SNAPSHOT.jar`);
    if (!existsSync(jar)) throw new Error(`Build ${service} with mvn verify first.`);
    launch(name, javaExecutable, ['-jar', jar, `--api.security.token.secret=${secret}`, ...args]);
  };
  launchJava('identity', 'identity-service', [`--server.port=${ports.identity}`, `--spring.datasource.url=jdbc:postgresql://localhost:5434/${database}`, '--spring.profiles.active=local', `--app.bootstrap-admin.email=${email}`, `--app.bootstrap-admin.password=${password}`]);
  launchJava('appointment', 'appointment-service', [`--server.port=${ports.appointment}`, `--spring.datasource.url=jdbc:postgresql://localhost:5433/${database}`, `--identity-service.url=http://localhost:${ports.identity}`]);
  const mongo = `mongodb://root:rootpassword@localhost:27017/${database}?authSource=admin&uuidRepresentation=standard`;
  launchJava('clinical', 'clinical-service', [`--server.port=${ports.clinical}`, `--spring.mongodb.uri=${mongo}`, `--spring.data.mongodb.uri=${mongo}`, `--identity.service.url=http://localhost:${ports.identity}`, `--appointment.service.url=http://localhost:${ports.appointment}`]);
  launchJava('gateway', 'api-gateway', [`--server.port=${ports.gateway}`, `--CLINICAL_SERVICE_URL=http://localhost:${ports.clinical}`, `--APPOINTMENT_SERVICE_URL=http://localhost:${ports.appointment}`, `--IDENTITY_SERVICE_URL=http://localhost:${ports.identity}`]);
  writeFileSync(proxyPath, JSON.stringify({ '/api/**': { target: `http://localhost:${ports.gateway}`, secure: false, changeOrigin: true, pathRewrite: { '^/api': '' } } }));
  launch('frontend', process.execPath, ['node_modules/@angular/cli/bin/ng.js', 'serve', '--host', '127.0.0.1', '--port', String(ports.frontend), '--proxy-config', proxyPath], resolve(root, 'frontend'));
  for (const [name, path] of [['identity', '/patients'], ['appointment', '/appointments'], ['clinical', '/records']]) await ready(`http://localhost:${ports[name]}${path}`);
  await ready(`http://127.0.0.1:${ports.frontend}`); await ready(base + '/patients');
  console.log('Services ready. Exercising Angular proxy → gateway → microservices.');
  const admin = (await login(email)).accessToken;
  const specialty = await request('/specialties', { token: admin, method: 'POST', status: 201, body: { nome: 'Clínica de integração' } });
  await request('/doctors', { token: admin, method: 'POST', status: 201, body: { nome: 'Médico Integração', email: 'doctor@integration.example', telefone: '11999990000', senha: password, crm: 'TESTE123', especialidadeId: specialty.id } });
  await request('/receptionists', { token: admin, method: 'POST', status: 201, body: { nome: 'Recepção Integração', email: 'reception@integration.example', telefone: '11999990000', senha: password } });
  for (const [index, seed] of [[1, '583942716'], [2, '721483695']]) await request('/patients', { method: 'POST', status: 201, body: { nome: `Paciente Integração ${index}`, email: `patient${index}@integration.example`, telefone: '11999990000', senha: password, cpf: cpf(seed) } });
  const doctor = (await login('doctor@integration.example')).accessToken;
  const reception = (await login('reception@integration.example')).accessToken;
  const patientSession = await login('patient1@integration.example'); const patient = patientSession.accessToken;
  const other = (await login('patient2@integration.example')).accessToken;
  await request('/admins', { token: patient, status: 403 });
  const dp = await request('/doctors/profile', { token: doctor });
  const pp = await request('/patients/profile', { token: patient });
  await request(`/patients/${pp.id}`, { token: other, status: 403 });
  for (const [resource, token] of [['admins', admin], ['receptionists', reception], ['doctors', doctor], ['patients', patient]]) {
    const profile = await request(`/${resource}/profile`, { token });
    await request(`/${resource}/profile`, { token, method: 'PATCH', body: { nome: profile.nome, email: profile.email, telefone: '11999991111' } });
    const updated = await request(`/${resource}/profile`, { token }); assert.equal(updated.telefone, '11999991111'); assertions++;
  }
  const date = new Date(); date.setDate(date.getDate() + 2); if (date.getDay() === 0) date.setDate(date.getDate() + 1);
  const dateString = `${date.getFullYear()}-${String(date.getMonth()+1).padStart(2,'0')}-${String(date.getDate()).padStart(2,'0')}T10:00:00`;
  const booking = { doctorId: dp.id, patientId: pp.id, dataHoraConsulta: dateString };
  await request('/appointments', { token: patient, method: 'POST', status: 201, body: booking });
  await request('/appointments', { token: patient, method: 'POST', status: 400, body: booking });
  assert.equal((await request('/appointments', { token: other })).length, 0); assertions++;
  const appointment = (await request('/appointments', { token: patient }))[0];
  await request(`/appointments/${appointment.id}/status`, { token: reception, method: 'PATCH', body: { status: 'EM_ESPERA' } });
  await request(`/appointments/${appointment.id}/status`, { token: doctor, method: 'PATCH', body: { status: 'EM_ATENDIMENTO' } });
  const record = await request('/records', { token: doctor, method: 'POST', status: 201, body: { patientId: pp.id, appointmentId: appointment.id, recordTitle: 'Consulta de teste', clinicalDescription: 'Registro persistido pela integração.', privateNotes: 'Nota privada', vitals: { weightKg: 70, heightMeters: 1.7, bloodPressure: '120/80' }, prescriptions: [{ medicationName: 'Medicamento de teste', dosage: 'Dose de teste', instructions: 'Prescrição fictícia exclusiva de teste.', validUntil: dateString.slice(0,10) }] } });
  assert.equal(record.doctorName, dp.nome); assertions++;
  const detail = await request(`/records/${record.id}`, { token: patient }); assert.equal(detail.privateNotes, null); assertions++;
  await request(`/records/${record.id}`, { token: other, status: 403 });
  await request(`/records/patient/${pp.id}`, { token: other, status: 403 });
  await request(`/records/patient/${pp.id}/prescriptions`, { token: other, status: 403 });
  assert.equal((await request(`/records/patient/${pp.id}/prescriptions`, { token: patient }))[0].medicationName, 'Medicamento de teste'); assertions++;
  assert.equal((await request(`/records/patient/${pp.id}/vitals/latest`, { token: patient })).weightKg, 70); assertions++;
  await request(`/records/${record.id}/addendum`, { token: doctor, method: 'PATCH', body: 'Adendo de integração', contentType: 'text/plain', status: 204 });
  await request(`/appointments/${appointment.id}/status`, { token: doctor, method: 'PATCH', body: { status: 'REALIZADA' } });
  assert.equal((await request('/appointments', { token: patient }))[0].status, 'REALIZADA'); assertions++;
  await request('/account/password', { token: patient, method: 'PATCH', body: { senhaAtual: password, novaSenha: password + 'new' }, status: 204 });
  const refreshed = await request('/auth/refresh', { method: 'POST', body: { refreshToken: patientSession.refreshToken } });
  await request('/auth/logout', { method: 'POST', body: { refreshToken: refreshed.refreshToken } });
  await request('/auth/refresh', { method: 'POST', body: { refreshToken: refreshed.refreshToken }, status: 401 });
  console.log(`PASS: ${assertions} checks; registration, four roles, profiles, booking, check-in, clinical records, prescriptions, privacy, password and token rotation.`);
} finally {
  for (const child of children.reverse()) {
    if (child.pid && child.exitCode === null && child.signalCode === null) {
      if (process.platform === 'win32') spawnSync('taskkill', ['/PID', String(child.pid), '/T', '/F'], { windowsHide: true, stdio: 'ignore' });
      else child.kill();
      await new Promise(resolve => { child.once('exit', resolve); setTimeout(resolve, 5000); });
    }
  }
  if (!/^integration_\d+_[a-f0-9]+$/.test(database)) throw new Error('Invalid disposable database name');
  for (const [container, existing] of created) docker('exec', container, 'psql', '-U', 'admin', '-d', existing, '-c', `DROP DATABASE ${database} WITH (FORCE)`);
  if (created.length) docker('exec', 'clinical_mongo_db', 'mongosh', '--quiet', '-u', 'root', '-p', 'rootpassword', '--authenticationDatabase', 'admin', '--eval', `db.getSiblingDB('${database}').dropDatabase()`);
  if (existsSync(proxyPath)) unlinkSync(proxyPath);
}
