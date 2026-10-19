$ErrorActionPreference = 'Stop'
[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Garante que os containers estão rodando antes de tentar inserir
$containers = @('identity_postgres_v2', 'appointment_postgres', 'clinical_mongo_db')
foreach ($c in $containers) {
    $running = docker inspect -f '{{.State.Running}}' $c 2>$null
    if ($running -ne 'true') {
        throw "O container '$c' não está em execução. Suba os bancos com docker compose antes de rodar este script."
    }
}

Write-Host "Iniciando carga de dados demonstrativos do Conecta Saúde..." -ForegroundColor Cyan

# ==============================================================================
# 1. IDENTITY SERVICE (PostgreSQL - db_identity)
# Senha padrão de todas as contas: Saude@2026
# ==============================================================================
$identitySql = @'
SET client_encoding = 'UTF8';

INSERT INTO specialties (nome) VALUES 
('Cardiologia'), 
('Clínica Geral'), 
('Pediatria'), 
('Dermatologia') 
ON CONFLICT (nome) DO NOTHING;

INSERT INTO users (id, nome, email, senha, telefone, tipo_user, ativo) VALUES
('10000000-0000-0000-0000-000000000001', 'Admin Demonstração', 'demo.admin@conectasaude.local', '$2a$10$Xk/msSTmFloIPu8JfBfwt.j2qg/9pGOqgDq74xDz0QG5EzeDTHJIO', '11990000001', 'ADMIN', true),
('20000000-0000-0000-0000-000000000001', 'Dra. Helena Costa', 'demo.helena@conectasaude.local', '$2a$10$Xk/msSTmFloIPu8JfBfwt.j2qg/9pGOqgDq74xDz0QG5EzeDTHJIO', '11990000011', 'MEDICO', true),
('20000000-0000-0000-0000-000000000002', 'Dr. Rafael Lima', 'demo.rafael@conectasaude.local', '$2a$10$Xk/msSTmFloIPu8JfBfwt.j2qg/9pGOqgDq74xDz0QG5EzeDTHJIO', '11990000012', 'MEDICO', true),
('20000000-0000-0000-0000-000000000003', 'Dra. Marina Alves', 'demo.marina@conectasaude.local', '$2a$10$Xk/msSTmFloIPu8JfBfwt.j2qg/9pGOqgDq74xDz0QG5EzeDTHJIO', '11990000013', 'MEDICO', true),
('30000000-0000-0000-0000-000000000001', 'Ana Souza', 'demo.ana@conectasaude.local', '$2a$10$Xk/msSTmFloIPu8JfBfwt.j2qg/9pGOqgDq74xDz0QG5EzeDTHJIO', '11990000021', 'RECEPCAO', true),
('30000000-0000-0000-0000-000000000002', 'Carlos Mendes', 'demo.carlos@conectasaude.local', '$2a$10$Xk/msSTmFloIPu8JfBfwt.j2qg/9pGOqgDq74xDz0QG5EzeDTHJIO', '11990000022', 'RECEPCAO', true),
('40000000-0000-0000-0000-000000000001', 'João Pereira', 'demo.joao@conectasaude.local', '$2a$10$Xk/msSTmFloIPu8JfBfwt.j2qg/9pGOqgDq74xDz0QG5EzeDTHJIO', '11990000031', 'PACIENTE', true),
('40000000-0000-0000-0000-000000000002', 'Beatriz Santos', 'demo.beatriz@conectasaude.local', '$2a$10$Xk/msSTmFloIPu8JfBfwt.j2qg/9pGOqgDq74xDz0QG5EzeDTHJIO', '11990000032', 'PACIENTE', true),
('40000000-0000-0000-0000-000000000003', 'Lucas Oliveira', 'demo.lucas@conectasaude.local', '$2a$10$Xk/msSTmFloIPu8JfBfwt.j2qg/9pGOqgDq74xDz0QG5EzeDTHJIO', '11990000033', 'PACIENTE', true),
('40000000-0000-0000-0000-000000000004', 'Mariana Rocha', 'demo.mariana@conectasaude.local', '$2a$10$Xk/msSTmFloIPu8JfBfwt.j2qg/9pGOqgDq74xDz0QG5EzeDTHJIO', '11990000034', 'PACIENTE', true),
('40000000-0000-0000-0000-000000000005', 'Pedro Henrique', 'demo.pedro@conectasaude.local', '$2a$10$Xk/msSTmFloIPu8JfBfwt.j2qg/9pGOqgDq74xDz0QG5EzeDTHJIO', '11990000035', 'PACIENTE', true),
('40000000-0000-0000-0000-000000000006', 'Sofia Martins', 'demo.sofia@conectasaude.local', '$2a$10$Xk/msSTmFloIPu8JfBfwt.j2qg/9pGOqgDq74xDz0QG5EzeDTHJIO', '11990000036', 'PACIENTE', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO doctors (id, crm, specialty_id) VALUES
('20000000-0000-0000-0000-000000000001', 'CRM-SP 123456', (SELECT id FROM specialties WHERE nome = 'Cardiologia')),
('20000000-0000-0000-0000-000000000002', 'CRM-SP 234567', (SELECT id FROM specialties WHERE nome = 'Clínica Geral')),
('20000000-0000-0000-0000-000000000003', 'CRM-SP 345678', (SELECT id FROM specialties WHERE nome = 'Pediatria'))
ON CONFLICT (id) DO NOTHING;

INSERT INTO patients (id, cpf) VALUES
('40000000-0000-0000-0000-000000000001', '58394271610'),
('40000000-0000-0000-0000-000000000002', '72148369554'),
('40000000-0000-0000-0000-000000000003', '15246387068'),
('40000000-0000-0000-0000-000000000004', '39058721462'),
('40000000-0000-0000-0000-000000000005', '64825179306'),
('40000000-0000-0000-0000-000000000006', '27614983577')
ON CONFLICT (id) DO NOTHING;

-- Caso o schema JPA utilize tabelas filhas para Admin e Recepção (Joined Inheritance), popula de forma segura:
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'admins') THEN
        INSERT INTO admins (id) VALUES ('10000000-0000-0000-0000-000000000001') ON CONFLICT (id) DO NOTHING;
    END IF;
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'receptionists') THEN
        INSERT INTO receptionists (id) VALUES 
        ('30000000-0000-0000-0000-000000000001'),
        ('30000000-0000-0000-0000-000000000002') 
        ON CONFLICT (id) DO NOTHING;
    END IF;
END $$;
'@

# ==============================================================================
# 2. APPOINTMENT SERVICE (PostgreSQL - appointment_db)
# Garante datas dentro do horário comercial (Seg-Sáb, 08h às 17h30, America/Sao_Paulo)
# ==============================================================================
$appointmentSql = @'
SET client_encoding = 'UTF8';
SET TIME ZONE 'America/Sao_Paulo';

INSERT INTO appointments (id, doctor_id, patient_id, data_hora_consulta, status, motivo_cancelamento) VALUES
-- Consultas futuras (pula domingo automaticamente caso caia no fim de semana)
('50000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 
    (CASE WHEN EXTRACT(DOW FROM CURRENT_DATE + 1) = 0 THEN CURRENT_DATE + 2 ELSE CURRENT_DATE + 1 END) + TIME '09:00:00', 
    'AGENDADA', NULL),
('50000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000002', 
    (CASE WHEN EXTRACT(DOW FROM CURRENT_DATE + 2) = 0 THEN CURRENT_DATE + 3 ELSE CURRENT_DATE + 2 END) + TIME '10:30:00', 
    'AGENDADA', NULL),

-- Fila de hoje (Em espera e Em atendimento)
('50000000-0000-0000-0000-000000000003', '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000003', 
    CURRENT_DATE + TIME '14:00:00', 'EM_ESPERA', NULL),
('50000000-0000-0000-0000-000000000004', '20000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000004', 
    CURRENT_DATE + TIME '13:30:00', 'EM_ATENDIMENTO', NULL),

-- Histórico e outros status
('50000000-0000-0000-0000-000000000005', '20000000-0000-0000-0000-000000000001', '40000000-0000-0000-0000-000000000001', 
    (CURRENT_DATE - 10) + TIME '14:00:00', 'REALIZADA', NULL),
('50000000-0000-0000-0000-000000000006', '20000000-0000-0000-0000-000000000003', '40000000-0000-0000-0000-000000000005', 
    (CURRENT_DATE - 3) + TIME '11:00:00', 'NAO_COMPARECEU', NULL),
('50000000-0000-0000-0000-000000000007', '20000000-0000-0000-0000-000000000002', '40000000-0000-0000-0000-000000000006', 
    (CASE WHEN EXTRACT(DOW FROM CURRENT_DATE + 5) = 0 THEN CURRENT_DATE + 6 ELSE CURRENT_DATE + 5 END) + TIME '15:30:00', 
    'CANCELADA', 'Paciente solicitou remarcação por compromisso de trabalho')
ON CONFLICT (id) DO NOTHING;
'@

# ==============================================================================
# 3. CLINICAL SERVICE (MongoDB - clinical_db)
# Inclui prontuários (medical_records) e exames em PDF (exams)
# ==============================================================================
$clinicalScript = @'
const d = db.getSiblingDB('clinical_db');

function record(id, patientId, doctorId, doctorName, specialty, appointmentId, title, description, date, weight, height, pressure, medication, dosage, instructions) {
  d.medical_records.updateOne({_id: ObjectId(id)}, {$setOnInsert: {
    patientId: UUID(patientId),
    doctorId: UUID(doctorId),
    doctorName: doctorName,
    doctorSpecialty: specialty,
    appointmentId: UUID(appointmentId),
    recordTitle: title,
    clinicalDescription: description,
    privateNotes: 'Registro demonstrativo para navegação no portal (visível apenas para médicos).',
    vitals: {weightKg: weight, heightMeters: height, bloodPressure: pressure},
    prescriptions: [{
      medicationName: medication,
      dosage: dosage,
      instructions: instructions,
      validUntil: new Date('2026-12-31T23:59:59Z')
    }],
    createdAt: new Date(date)
  }}, {upsert: true});
}

record(
  '650000000000000000000001',
  '40000000-0000-0000-0000-000000000001',
  '20000000-0000-0000-0000-000000000001',
  'Dra. Helena Costa',
  'Cardiologia',
  '50000000-0000-0000-0000-000000000005',
  'Avaliação cardiológica de rotina',
  'Paciente sem queixas importantes, ritmo cardíaco regular e pressão arterial controlada.',
  '2026-10-06T14:00:00Z',
  74.2, 1.75, '120/80',
  'Losartana 50 mg', '1 comprimido', 'Tomar 1 comprimido pela manhã, em jejum.'
);

record(
  '650000000000000000000002',
  '40000000-0000-0000-0000-000000000002',
  '20000000-0000-0000-0000-000000000002',
  'Dr. Rafael Lima',
  'Clínica Geral',
  '50000000-0000-0000-0000-000000000002',
  'Consulta preventiva anual',
  'Orientações gerais de alimentação equilibrada, higiene do sono e manutenção de atividade física.',
  '2026-09-28T13:00:00Z',
  61.8, 1.65, '110/70',
  'Vitamina D3 2000 UI', '1 cápsula', 'Tomar 1 cápsula junto ao almoço diariamente.'
);

record(
  '650000000000000000000003',
  '40000000-0000-0000-0000-000000000003',
  '20000000-0000-0000-0000-000000000001',
  'Dra. Helena Costa',
  'Cardiologia',
  '50000000-0000-0000-0000-000000000003',
  'Acompanhamento de dislipidemia',
  'Acompanhamento clínico em andamento; paciente trouxe exames laboratoriais recentes.',
  '2026-10-14T13:00:00Z',
  80.1, 1.78, '130/85',
  'Atorvastatina 20 mg', '1 comprimido', 'Tomar 1 comprimido à noite após o jantar.'
);

// Carga opcional de Exames (caso a collection 'exams' seja usada para listagem direta no Mongo)
const pdfBytes = BinData(0, Buffer.from('%PDF-1.4\n1 0 obj\n<< /Type /Catalog >>\nendobj\n%%EOF').toString('base64'));
function exam(id, patientId, doctorId, title, fileName, date) {
  d.exams.updateOne({_id: ObjectId(id)}, {$setOnInsert: {
    patientId: UUID(patientId),
    doctorId: UUID(doctorId),
    title: title,
    fileName: fileName,
    contentType: 'application/pdf',
    fileSize: 48,
    data: pdfBytes,
    content: pdfBytes,
    createdAt: new Date(date),
    uploadedAt: new Date(date)
  }}, {upsert: true});
}

exam('660000000000000000000001', '40000000-0000-0000-0000-000000000001', '20000000-0000-0000-0000-000000000001', 'Eletrocardiograma de Repouso', 'ecg-joao-pereira.pdf', '2026-10-06T14:30:00Z');
exam('660000000000000000000002', '40000000-0000-0000-0000-000000000002', '20000000-0000-0000-0000-000000000002', 'Hemograma Completo e Vitamina D', 'hemograma-beatriz.pdf', '2026-09-28T13:30:00Z');

printjson({
  medicalRecords: d.medical_records.countDocuments(),
  exams: d.exams.countDocuments()
});
'@

# Execução nos containers
Write-Host "-> Populando db_identity (PostgreSQL)..." -ForegroundColor Yellow
$identitySql | docker exec -i identity_postgres_v2 psql -v ON_ERROR_STOP=1 -U admin -d db_identity

Write-Host "-> Populando appointment_db (PostgreSQL)..." -ForegroundColor Yellow
$appointmentSql | docker exec -i appointment_postgres psql -v ON_ERROR_STOP=1 -U admin -d appointment_db

Write-Host "-> Populando clinical_db (MongoDB)..." -ForegroundColor Yellow
$clinicalScript | docker exec -i clinical_mongo_db mongosh --quiet -u root -p rootpassword --authenticationDatabase admin

Write-Host ""
Write-Host "==========================================================" -ForegroundColor Green
Write-Host " Carga de demonstração concluída com sucesso!" -ForegroundColor Green
Write-Host "==========================================================" -ForegroundColor Green
Write-Host "Senha única para todas as contas: Saude@2026"
Write-Host "  [Admin]     demo.admin@conectasaude.local"
Write-Host "  [Médico]    demo.helena@conectasaude.local (Cardiologia)"
Write-Host "  [Médico]    demo.rafael@conectasaude.local (Clínica Geral)"
Write-Host "  [Recepção]  demo.ana@conectasaude.local"
Write-Host "  [Paciente]  demo.joao@conectasaude.local"
Write-Host "  [Paciente]  demo.beatriz@conectasaude.local"

# (Opcional) Publica um exame real via Gateway caso os microsserviços estejam rodando na porta 8080
try {
    $loginResp = Invoke-RestMethod -Uri "http://localhost:8080/auth/login" -Method Post -ContentType "application/json" -Body '{"email":"demo.helena@conectasaude.local","senha":"Saude@2026","manterConectado":false}' -ErrorAction Stop
    $token = $loginResp.accessToken
    
    $form = @{
        patientId = '40000000-0000-0000-0000-000000000001'
        title     = 'Check-up Cardiológico (Via API)'
        file      = [System.IO.FileInfo]::new("$PSScriptRoot\..\README.md") # Ou qualquer PDF local
    }
    # No PowerShell 7+, -Form monta o multipart/form-data automaticamente
    Invoke-RestMethod -Uri "http://localhost:8080/exams" -Method Post -Headers @{Authorization = "Bearer $token"} -Form $form | Out-Null
    Write-Host "-> Exame publicado via API com sucesso!" -ForegroundColor Green
} catch {
    Write-Host "-> (Aviso) Gateway offline na porta 8080; pulando upload de exame via HTTP." -ForegroundColor DarkGray
}