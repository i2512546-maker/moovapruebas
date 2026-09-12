-- ============================================================
--  RapiJob - Seed de Datos Simulados
--  Objetivo: poblar KPIs de PLATAFORMA + reputación de técnicos.
--  Todas las PK son UUID válidas (version 4, variant 9).
--
--  CONTRASEÑAS: ver scripts/seed-passwords.js (hashes reales vía bcryptjs).
--  Usuario admin/client/tech/supervisor usan: password123
--  Los KPIs no requieren login -> funcionan tras este seed.
-- ============================================================
SET session_replication_on = ON;
TRUNCATE TABLE payments, job_reviews, review_validations, job_assignments,
              job_applications, documents, notifications, jobs,
              technician_certifications, technician_specialties,
              certifications, specialties, profiles, users,
              platform_alert_rules, commission_rules
              RESTART IDENTITY CASCADE;
SET session_replication_on = OFF;

-- ============================================================
-- UUID MASTER MAP (para que las referencias sean consistentes)
--   clientes: 0...010 / 0...011
--   técnicos : 0...020 / 021 / 022 / 023
--   jobs   : 10010000-1xxx-4001-9001-0000000000xx  (j001..j020)
--   pays   : 20010000-1xxx-4001-9002-...             (p001..p013)
--   reviews: 30010000-1xxx-4001-9003-...             (r001..r013)
--   vals   : 40010000-1xxx-4001-9004-...             (v001..v013)
--   docs   : 50010000-00xx-4001-9005-...             (doc01..doc03)
--   apps   : 60010000-1xxx-4001-9006-...             (ap001..ap014)
--   notif  : 70010000-1xxx-4001-9007-...             (n_001..n_012)
-- ============================================================

-- ------------------------------------------------------------
-- 1) USERS (auth + roles)  [password placeholder, regenerar vía scripts/seed-passwords.js]
-- ------------------------------------------------------------
DO $$
DECLARE
  ph TEXT := '$2b$12$abcdefghijklmnopqrstuuAbCdEfGhIjKlMnOpQrStUvWxYz01234567';
BEGIN
  INSERT INTO users (id,email,phone,password,role,status,verified,created_at) VALUES
    ('a0000000-0000-0000-0000-000000000001','admin@rapijob.com','+1000000001',ph,'admin','active',TRUE,now()-'60 days'::interval),
    ('a0000000-0000-0000-0000-000000000002','sup@rapijob.com','+1000000002',ph,'supervisor','active',TRUE,now()-'60 days'::interval),
    ('a0000000-0000-0000-0000-000000000010','cliente.it@corp.com','+1000000010',ph,'client','active',TRUE,now()-'45 days'::interval),
    ('a0000000-0000-0000-0000-000000000011','cliente.hogar@corp.com','+1000000011',ph,'client','active',TRUE,now()-'45 days'::interval),
    ('a0000000-0000-0000-0000-000000000020','ana.tech@rapijob.com','+1000000020',ph,'technician','active',TRUE,now()-'40 days'::interval),
    ('a0000000-0000-0000-0000-000000000021','luis.tech@rapijob.com','+1000000021',ph,'technician','active',TRUE,now()-'38 days'::interval),
    ('a0000000-0000-0000-0000-000000000022','carlos.tech@rapijob.com','+1000000022',ph,'technician','active',TRUE,now()-'35 days'::interval),
    ('a0000000-0000-0000-0000-000000000023','diana.tech@rapijob.com','+1000000033',ph,'technician','active',TRUE,now()-'33 days'::interval);
  RAISE NOTICE 'users inserted';
END $$;

-- ------------------------------------------------------------
-- 2) PROFILES
-- ------------------------------------------------------------
INSERT INTO profiles(user_id,first_name,last_name,bio,location_lat,location_lng,location_label,service_radius_km,hourly_rate,verified_at,created_at)
VALUES
 ('a0000000-0000-0000-0000-000000000010','TechCorp','Soluciones','Empresa de software',40.4168,-3.7038,'Madrid, España',50,0,NULL,now()-'45 days'::interval),
 ('a0000000-0000-0000-0000-000000000011','HogarSergio','Construcciones','Constructora',40.4381,-3.6919,'Alcobendas, España',40,0,NULL,now()-'45 days'::interval),
 ('a0000000-0000-0000-0000-000000000020','Ana','García','Full-stack, redes y soporte',40.4180,-3.6940,'Centro, Madrid',25,45.00,now()-'30 days'::interval,now()-'30 days'::interval),
 ('a0000000-0000-0000-0000-000000000021','Luis','Pérez','Electricista certificado',40.4300,-3.6850,'Chueca, Madrid',20,50.00,now()-'25 days'::interval,now()-'28 days'::interval),
 ('a0000000-0000-0000-0000-000000000022','Carlos','Ruiz','Fontanero especializado',40.4100,-3.6700,'Retiro, Madrid',15,40.00,now()-'10 days'::interval,now()-'35 days'::interval),
 ('a0000000-0000-0000-0000-000000000023','Diana','López','Mantenimiento industrial + IT',40.4500,-3.6800,'Barajas, Madrid',35,55.00,now()-'20 days'::interval,now()-'33 days'::interval);

-- ------------------------------------------------------------
-- 3) SPECIALTIES (extensible a cualquier tipo de técnico)
-- ------------------------------------------------------------
INSERT INTO specialties(id,name,description)
VALUES
 ('b0000000-0000-0000-0000-000000000001','IT Support','Hardware, software, redes y soporte'),
 ('b0000000-0000-0000-0000-000000000002','Electricidad','Instalaciones eléctricas, cuadros, iluminación'),
 ('b0000000-0000-0000-0000-000000000003','Plomería','Tuberías, fontanería, fontanía de emergencia'),
 ('b0000000-0000-0000-0000-000000000004','Mantenimiento Industrial','Maquinaria, HVAC, mantenimiento predictivo');

-- ------------------------------------------------------------
-- 4) TECHNICIAN_SPECIALTIES
-- ------------------------------------------------------------
INSERT INTO technician_specialties(technician_id,specialty_id,experience_years)
VALUES
 ('a0000000-0000-0000-0000-000000000020','b0000000-0000-0000-0000-000000000001',5),   -- Ana: IT
 ('a0000000-0000-0000-0000-000000000021','b0000000-0000-0000-0000-000000000002',8),   -- Luis: Electricidad
 ('a0000000-0000-0000-0000-000000000022','b0000000-0000-0000-0000-000000000003',6),   -- Carlos: Plomería
 ('a0000000-0000-0000-0000-000000000023','b0000000-0000-0000-0000-000000000004',7),   -- Diana: Mantenimiento
 ('a0000000-0000-0000-0000-000000000023','b0000000-0000-0000-0000-000000000001',3);   -- Diana también IT

-- ------------------------------------------------------------
-- 5) CERTIFICATIONS (catálogo)
-- ------------------------------------------------------------
INSERT INTO certifications(id,name,issuing_body)
VALUES
 ('c0000000-0000-0000-0000-000000000001','AWS Certified Solutions Architect','Amazon'),
 ('c0000000-0000-0000-0000-000000000002','Cisco CCNA','Cisco'),
 ('c0000000-0000-0000-0000-000000000003','Certificación Electricista Básica','AEE'),
 ('c0000000-0000-0000-0000-000000000004','Certificación de Fontanero Oficial','Ministerio Fomento'),
 ('c0000000-0000-0000-0000-000000000005','Certificación de Aptitud Solar Térmica','IDAE');

-- ------------------------------------------------------------
-- 6) TECHNICIAN_CERTIFICATIONS
--   - Ana: AWS válida, CCNA válida
--   - Luis: Electricidad válida
--   - Carlos: Plomería VENCIDA (validación fallida por expiración)
--   - Diana: Solar válida + CCNA
-- ------------------------------------------------------------
INSERT INTO technician_certifications
  (id,technician_id,certification_id,document_url,issued_at,expires_at,validation_status,validated_by,validated_at)
VALUES
 ('d0000000-0000-0000-0000-000000000001','a0000000-0000-0000-0000-000000000020',
  'c0000000-0000-0000-0000-000000000001','https://s3/ana_aws.pdf','2024-03-01','2025-03-01','valid','a0000000-0000-0000-0000-000000000001',now()-'20 days'::interval),
 ('d0000000-0000-0000-0000-000000000002','a0000000-0000-0000-0000-000000000020',
  'c0000000-0000-0000-0000-000000000002','https://s3/ana_ccna.pdf','2023-06-01','2025-06-01','valid','a0000000-0000-0000-0000-000000000001',now()-'20 days'::interval),
 ('d0000000-0000-0000-0000-000000000003','a0000000-0000-0000-0000-000000000021',
  'c0000000-0000-0000-0000-000000000003','https://s3/luis_elec.pdf','2022-01-01','2025-01-01','valid','a0000000-0000-0000-0000-000000000001',now()-'25 days'::interval),
 ('d0000000-0000-0000-0000-000000000004','a0000000-0000-0000-0000-000000000022',
  'c0000000-0000-0000-0000-000000000004','https://s3/carlos_plom.pdf','2021-01-01','2024-01-01','rejected','a0000000-0000-0000-0000-000000000001',now()-'5 days'::interval),
 ('d0000000-0000-0000-0000-000000000005','a0000000-0000-0000-0000-000000000023',
  'c0000000-0000-0000-0000-000000000005','https://s3/diana_solar.pdf','2024-05-01','2026-05-01','valid','a0000000-0000-0000-0000-000000000001',now()-'15 days'::interval),
 ('d0000000-0000-0000-0000-000000000006','a0000000-0000-0000-0000-000000000023',
  'c0000000-0000-0000-0000-000000000002','https://s3/diana_ccna.pdf','2023-02-01','2025-02-01','valid','a0000000-0000-0000-0000-000000000001',now()-'15 days'::interval);

-- ------------------------------------------------------------
-- 7) COMMISSION RULES (default 15%, IT 12%)
-- ------------------------------------------------------------
INSERT INTO commission_rules (id,specialty_id,rate_pct,min_amount,active)
VALUES
 ('e0000000-0000-0000-0000-000000000001',NULL,15.00,0,TRUE),
 ('e0000000-0000-0000-0000-000000000002','b0000000-0000-0000-0000-000000000001',12.00,0,TRUE);

-- ------------------------------------------------------------
-- 8) JOBS  (j001..j020 = UUIDs en mapa; fechas relativas a NOW)
--  ClienteIT(0..10) -> jobs IT ; ClienteHogar(0..11) -> jobs elec/plom/mant
--  Estados: open/in_progress/completed/cancelled
-- ------------------------------------------------------------
INSERT INTO jobs
  (id,client_id,title,description,specialty_id,budget_min,budget_max,
   location_lat,location_lng,location_label,is_remote,urgency,status,
   deadline_at,assigned_to,completed_at,cancelled_at,cancellation_reason,created_at)
VALUES
-- --- Semana -1 (última): 4 jobs ---
 ('10010000-1001-4001-9001-000000000001','a0000000-0000-0000-0000-000000000010','Soporte servidor caído','Servidor producción down',
  'b0000000-0000-0000-0000-000000000001',400,600,40.418,-3.693,'Madrid Centro',FALSE,'urgent','completed',
   NULL,'a0000000-0000-0000-0000-000000000020',now()-'3 days'::interval,NULL,NULL,now()-'5 days'::interval),
 ('10010000-1002-4001-9001-000000000002','a0000000-0000-0000-0000-000000000010','Mantenimiento redes oficina','Switch nueva sucursal',
  'b0000000-0000-0000-0000-000000000001',800,1200,40.430,-3.680,'Chueca',FALSE,'normal','completed',
   NULL,'a0000000-0000-0000-0000-000000000023',now()-'2 days'::interval,NULL,NULL,now()-'6 days'::interval),
 ('10010000-1003-4001-9001-000000000003','a0000000-0000-0000-0000-000000000011','Reparación electrodomésticos','Horno y lavavajillas',
  'b0000000-0000-0000-0000-000000000002',200,350,40.410,-3.670,'Retiro',FALSE,'high','cancelled',
   NULL,'a0000000-0000-0000-0000-000000000021',NULL,now()-'1 day'::interval,'El cliente canceló',now()-'3 days'::interval),
 ('10010000-1004-4001-9001-000000000004','a0000000-0000-0000-0000-000000000011','Revisión instalación solar','Monitor deplacado',
  'b0000000-0000-0000-0000-000000000002',1500,2500,40.450,-3.680,'Barajas',FALSE,'urgent','in_progress',
   NULL,'a0000000-0000-0000-0000-000000000023',NULL,NULL,NULL,now()-'2 days'::interval),

-- --- Semana -2: 4 jobs ---
 ('10010000-1005-4001-9001-000000000005','a0000000-0000-0000-0000-000000000010','Instalación cableado estructurado','Oficina nueva planta baja',
  'b0000000-0000-0000-0000-000000000001',1000,1500,40.420,-3.690,'Madrid Centro',FALSE,'normal','completed',
   NULL,'a0000000-0000-0000-0000-000000000023',now()-'8 days'::interval,NULL,NULL,now()-'10 days'::interval),
 ('10010000-1006-4001-9001-000000000006','a0000000-0000-0000-0000-000000000011','Reparación fuga agua','Fuga tubería conducto',
  'b0000000-0000-0000-0000-000000000003',300,500,40.415,-3.675,'Retiro',FALSE,'high','completed',
   NULL,'a0000000-0000-0000-0000-000000000022',now()-'7 days'::interval,NULL,NULL,now()-'9 days'::interval),
 ('10010000-1007-4001-9001-000000000007','a0000000-0000-0000-0000-000000000010','Backup y migración servidores','Migración a la nube',
  'b0000000-0000-0000-0000-000000000001',2000,3000,40.416,-3.694,'Madrid Centro',FALSE,'urgent','cancelled',
   NULL,'a0000000-0000-0000-0000-000000000020',NULL,now()-'6 days'::interval,'Presupuesto rechazado',now()-'8 days'::interval),
 ('10010000-1008-4001-9001-000000000008','a0000000-0000-0000-0000-000000000011','Instalación iluminación LED','Reforma comercial',
  'b0000000-0000-0000-0000-000000000002',900,1400,40.432,-3.682,'Chueca',FALSE,'normal','completed',
   NULL,'a0000000-0000-0000-0000-000000000021',now()-'9 days'::interval,NULL,NULL,now()-'11 days'::interval),

-- --- Semana -3: 4 jobs ---
 ('10010000-1009-4001-9001-000000000009','a0000000-0000-0000-0000-000000000010','Configuración router empresa','VPN sucursales',
  'b0000000-0000-0000-0000-000000000001',500,800,40.418,-3.693,'Madrid Centro',FALSE,'normal','completed',
   NULL,'a0000000-0000-0000-0000-000000000020',now()-'13 days'::interval,NULL,NULL,now()-'15 days'::interval),
 ('10010000-1010-4001-9001-000000000010','a0000000-0000-0000-0000-000000000011','Reparación bomba agua','Fallo bomba circulador',
  'b0000000-0000-0000-0000-000000000003',450,700,40.410,-3.670,'Retiro',FALSE,'urgent','completed',
   NULL,'a0000000-0000-0000-0000-000000000022',now()-'11 days'::interval,NULL,NULL,now()-'13 days'::interval),
 ('10010000-1011-4001-9001-000000000011','a0000000-0000-0000-0000-000000000010','Auditoría seguridad red','Pen test preventivo',
  'b0000000-0000-0000-0000-000000000001',1800,2500,40.416,-3.694,'Madrid Centro',FALSE,'high','open',
   now()-'5 days'::interval,NULL,NULL,NULL,now()-'12 days'::interval),
 ('10010000-1012-4001-9001-000000000012','a0000000-0000-0000-0000-000000000011','Mantenimiento preventivo HVAC','Unidad split terraza',
  'b0000000-0000-0000-0000-000000000004',1200,1800,40.450,-3.680,'Barajas',FALSE,'normal','completed',
   NULL,'a0000000-0000-0000-0000-000000000023',now()-'12 days'::interval,NULL,NULL,now()-'14 days'::interval),

-- --- Semana -4: 4 jobs ---
 ('10010000-1013-4001-9001-000000000013','a0000000-0000-0000-0000-000000000010','Despliegue software punto de venta','10 terminales',
  'b0000000-0000-0000-0000-000000000001',600,900,40.430,-3.680,'Chueca',FALSE,'normal','completed',
   NULL,'a0000000-0000-0000-0000-000000000020',now()-'17 days'::interval,NULL,NULL,now()-'19 days'::interval),
 ('10010000-1014-4001-9001-000000000014','a0000000-0000-0000-0000-000000000011','Sustitución grifo doble','Cocina comercial',
  'b0000000-0000-0000-0000-000000000003',150,250,40.412,-3.672,'Retiro',FALSE,'low','completed',
   NULL,'a0000000-0000-0000-0000-000000000022',now()-'16 days'::interval,NULL,NULL,now()-'18 days'::interval),
 ('10010000-1015-4001-9001-000000000015','a0000000-0000-0000-0000-000000000010','Soporte remoto usuarios','Limpieza malware 8 equipos',
  'b0000000-0000-0000-0000-000000000001',300,500,40.418,-3.693,'Madrid Centro',TRUE,'normal','cancelled',
   NULL,'a0000000-0000-0000-0000-000000000023',NULL,now()-'15 days'::interval,'Cliente no dispondrá',now()-'17 days'::interval),
 ('10010000-1016-4001-9001-000000000016','a0000000-0000-0000-0000-000000000011','Revisión cuadro eléctrico','Edificio residencial',
  'b0000000-0000-0000-0000-000000000002',700,1100,40.432,-3.682,'Chueca',TRUE,'normal','completed',
   NULL,'a0000000-0000-0000-0000-000000000021',now()-'18 days'::interval,NULL,NULL,now()-'20 days'::interval),

-- --- Semana -5 (más antigua): 4 jobs ---
 ('10010000-1017-4001-9001-000000000017','a0000000-0000-0000-0000-000000000010','Recuperación disco crítico','Raid 5 reconstruir',
  'b0000000-0000-0000-0000-000000000001',900,1300,40.416,-3.694,'Madrid Centro',FALSE,'urgent','completed',
   NULL,'a0000000-0000-0000-0000-000000000020',now()-'21 days'::interval,NULL,NULL,now()-'23 days'::interval),
 ('10010000-1018-4001-9001-000000000018','a0000000-0000-0000-0000-000000000011','Sustitución válvula retención','Obra nueva',
  'b0000000-0000-0000-0000-000000000003',200,350,40.410,-3.670,'Retiro',FALSE,'normal','completed',
   NULL,'a0000000-0000-0000-0000-000000000022',now()-'19 days'::interval,NULL,NULL,now()-'21 days'::interval),
 ('10010000-1019-4001-9001-000000000019','a0000000-0000-0000-0000-000000000010','Soporte servidor caído','Base de datos caída',
  'b0000000-0000-0000-0000-000000000001',350,600,40.418,-3.693,'Madrid Centro',FALSE,'urgent','in_progress',
   now()-'14 days'::interval,'a0000000-0000-0000-0000-000000000020',NULL,NULL,NULL,now()-'22 days'::interval),
 ('10010000-1020-4001-9001-000000000020','a0000000-0000-0000-0000-000000000011','Mantenimiento maquinaria productiva','Línea embotellado',
  'b0000000-0000-0000-0000-000000000004',2200,3200,40.450,-3.680,'Barajas',FALSE,'high','completed',
   NULL,'a0000000-0000-0000-0000-000000000023',now()-'23 days'::interval,NULL,NULL,now()-'25 days'::interval);

-- ------------------------------------------------------------
-- 9) JOB_APPLICATIONS (ap001..ap008) — aplicaciones iniciadas por técnicos
--    engagement variado: Ana(4), Diana(2), Carlos(2), Luis(0)
-- ------------------------------------------------------------
INSERT INTO job_applications (id,job_id,technician_id,proposed_price,status,created_at,updated_at)
VALUES
 -- Ana (IT) aplica y gana: j001, j009, j013, j019
 ('60010000-1001-4001-9006-000000000001','10010000-1001-4001-9001-000000000001','a0000000-0000-0000-0000-000000000020',450,'accepted',now()-'5 days'::interval,now()-'5 days'::interval),
 ('60010000-1002-4001-9006-000000000002','10010000-1009-4001-9001-000000000009','a0000000-0000-0000-0000-000000000020',650,'accepted',now()-'15 days'::interval,now()-'15 days'::interval),
 ('60010000-1003-4001-9006-000000000003','10010000-1013-4001-9001-000000000013','a0000000-0000-0000-0000-000000000020',700,'accepted',now()-'19 days'::interval,now()-'19 days'::interval),
 ('60010000-1004-4001-9006-000000000004','10010000-1019-4001-9001-000000000019','a0000000-0000-0000-0000-000000000020',500,'accepted',now()-'22 days'::interval,now()-'22 days'::interval),
 -- Diana (mantenimiento+IT) aplica y gana: j005, j004
 ('60010000-1005-4001-9006-000000000005','10010000-1005-4001-9001-000000000005','a0000000-0000-0000-0000-000000000023',1300,'accepted',now()-'10 days'::interval,now()-'10 days'::interval),
 ('60010000-1006-4001-9006-000000000006','10010000-1004-4001-9001-000000000004','a0000000-0000-0000-0000-000000000023',2000,'applied',now()-'2 days'::interval,now()-'2 days'::interval),
 -- Carlos (plomería) aplica y gana: j006, j014
 ('60010000-1007-4001-9006-000000000007','10010000-1006-4001-9001-000000000006','a0000000-0000-0000-0000-000000000022',400,'accepted',now()-'9 days'::interval,now()-'9 days'::interval),
 ('60010000-1008-4001-9006-000000000008','10010000-1014-4001-9001-000000000014','a0000000-0000-0000-0000-000000000022',200,'accepted',now()-'18 days'::interval,now()-'18 days'::interval);

-- ------------------------------------------------------------
-- 10) JOB_ASSIGNMENTS (historial de ofertas)
--     accepted_at = técnico aceptó ; rejected_at = técnico rechazó
--     assigned_to del job = el técnico que ACCEPTÓ.
--     Variedad de tasa de aceptación: Ana/Diana 83%, Luis 67%, Carlos 57%
-- ------------------------------------------------------------
INSERT INTO job_assignments (job_id,technician_id,assigned_by,assigned_at,accepted_at,rejected_at,rejection_reason)
VALUES
 -- --- ACCEPTED (16: todos los jobs assigned_to) ---
 ('10010000-1001-4001-9001-000000000001','a0000000-0000-0000-0000-000000000020','a0000000-0000-0000-0000-000000000010',now()-'5 days'::interval,now()-'4 days,23 hours'::interval,NULL,NULL),
 ('10010000-1002-4001-9001-000000000002','a0000000-0000-0000-0000-000000000023','a0000000-0000-0000-0000-000000000010',now()-'4 days'::interval,now()-'3 days,22 hours'::interval,NULL,NULL),
 ('10010000-1005-4001-9001-000000000005','a0000000-0000-0000-0000-000000000023','a0000000-0000-0000-0000-000000000010',now()-'10 days'::interval,now()-'9 days,22 hours'::interval,NULL,NULL),
 ('10010000-1009-4001-9001-000000000009','a0000000-0000-0000-0000-000000000020','a0000000-0000-0000-0000-000000000010',now()-'15 days'::interval,now()-'14 days,23 hours'::interval,NULL,NULL),
 ('10010000-1013-4001-9001-000000000013','a0000000-0000-0000-0000-000000000020','a0000000-0000-0000-0000-000000000010',now()-'19 days'::interval,now()-'18 days,22 hours'::interval,NULL,NULL),
 ('10010000-1017-4001-9001-000000000017','a0000000-0000-0000-0000-000000000020','a0000000-0000-0000-0000-000000000010',now()-'22 days'::interval,now()-'21 days,23 hours'::interval,NULL,NULL),
 ('10010000-1019-4001-9001-000000000019','a0000000-0000-0000-0000-000000000020','a0000000-0000-0000-0000-000000000010',now()-'22 days'::interval,now()-'21 days,22 hours'::interval,NULL,NULL),
 ('10010000-1004-4001-9001-000000000004','a0000000-0000-0000-0000-000000000023','a0000000-0000-0000-0000-000000000011',now()-'2 days'::interval,now()-'1 day,23 hours'::interval,NULL,NULL),
 ('10010000-1006-4001-9001-000000000006','a0000000-0000-0000-0000-000000000022','a0000000-0000-0000-0000-000000000011',now()-'9 days'::interval,now()-'8 days,23 hours'::interval,NULL,NULL),
 ('10010000-1010-4001-9001-000000000010','a0000000-0000-0000-0000-000000000022','a0000000-0000-0000-0000-000000000011',now()-'13 days'::interval,now()-'12 days,23 hours'::interval,NULL,NULL),
 ('10010000-1014-4001-9001-000000000014','a0000000-0000-0000-0000-000000000022','a0000000-0000-0000-0000-000000000011',now()-'18 days'::interval,now()-'17 days,23 hours'::interval,NULL,NULL),
 ('10010000-1018-4001-9001-000000000018','a0000000-0000-0000-0000-000000000022','a0000000-0000-0000-0000-000000000011',now()-'20 days'::interval,now()-'19 days,23 hours'::interval,NULL,NULL),
 ('10010000-1008-4001-9001-000000000008','a0000000-0000-0000-0000-000000000021','a0000000-0000-0000-0000-000000000011',now()-'10 days'::interval,now()-'9 days,22 hours'::interval,NULL,NULL),
 ('10010000-1016-4001-9001-000000000016','a0000000-0000-0000-0000-000000000021','a0000000-0000-0000-0000-000000000011',now()-'19 days'::interval,now()-'18 days,23 hours'::interval,NULL,NULL),
 ('10010000-1012-4001-9001-000000000012','a0000000-0000-0000-0000-000000000023','a0000000-0000-0000-0000-000000000011',now()-'13 days'::interval,now()-'12 days,23 hours'::interval,NULL,NULL),
 ('10010000-1020-4001-9001-000000000020','a0000000-0000-0000-0000-000000000023','a0000000-0000-0000-0000-000000000011',now()-'24 days'::interval,now()-'23 days,22 hours'::interval,NULL,NULL),
 -- --- REJECTED (6 ofertas rechazadas → genera spread de aceptación) ---
 ('10010000-1002-4001-9001-000000000002','a0000000-0000-0000-0000-000000000020',NULL,now()-'5 days'::interval,NULL,now()-'4 days'::interval,'Ya tengo prioridad'),
 ('10010000-1009-4001-9001-000000000009','a0000000-0000-0000-0000-000000000022',NULL,now()-'15 days'::interval,NULL,now()-'14 days'::interval,'No especialidad IT'),
 ('10010000-1013-4001-9001-000000000013','a0000000-0000-0000-0000-000000000022',NULL,now()-'19 days'::interval,NULL,now()-'18 days'::interval,'No especialidad IT'),
 ('10010000-1017-4001-9001-000000000017','a0000000-0000-0000-0000-000000000022',NULL,now()-'22 days'::interval,NULL,now()-'21 days'::interval,'No especialidad IT'),
 ('10010000-1001-4001-9001-000000000001','a0000000-0000-0000-0000-000000000021',NULL,now()-'5 days'::interval,NULL,now()-'4 days'::interval,'No IT'),
 ('10010000-1001-4001-9001-000000000001','a0000000-0000-0000-0000-000000000023',NULL,now()-'5 days'::interval,NULL,now()-'4 days'::interval,'Fuera de zona');

-- ------------------------------------------------------------
-- 11) JOB_REVIEWS (r001..r013)  ratings 1-5
--   Ana: 4 jobs, ratings 4-5 (avg ~4.75)
--   Luis: 2 jobs, ratings 4-5 (avg 4.5)
--   Carlos: 3 jobs, ratings 4-5 (avg ~4.3)
--   Diana: 3 jobs, ratings 5 (avg 5.0, first-time-fix alto)
-- ------------------------------------------------------------
INSERT INTO job_reviews (id,job_id,reviewer_id,reviewee_id,rating,comment,created_at)
VALUES
 ('30010000-1001-4001-9003-000000000001','10010000-1001-4001-9001-000000000001','a0000000-0000-0000-0000-000000000010','a0000000-0000-0000-0000-000000000020',5,'Excelente, servidor restaurado en 1h',now()-'3 days'::interval),
 ('30010000-1002-4001-9003-000000000002','10010000-1005-4001-9001-000000000005','a0000000-0000-0000-0000-000000000010','a0000000-0000-0000-0000-000000000023',5,'Cableado impecable',now()-'8 days'::interval),
 ('30010000-1003-4001-9003-000000000003','10010000-1009-4001-9001-000000000009','a0000000-0000-0000-0000-000000000010','a0000000-0000-0000-0000-000000000020',4,'Router configurado, entregado a tiempo',now()-'13 days'::interval),
 ('30010000-1004-4001-9003-000000000004','10010000-1013-4001-9001-000000000013','a0000000-0000-0000-0000-000000000010','a0000000-0000-0000-0000-000000000020',5,'Deploy sin incidencias',now()-'16 days'::interval),
 ('30010000-1005-4001-9003-000000000005','10010000-1017-4001-9001-000000000017','a0000000-0000-0000-0000-000000000010','a0000000-0000-0000-0000-000000000020',5,'Recuperación perfecta',now()-'20 days'::interval),
 ('30010000-1006-4001-9003-000000000006','10010000-1008-4001-9001-000000000008','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000021',4,'Iluminación correcta',now()-'9 days'::interval),
 ('30010000-1007-4001-9003-000000000007','10010000-1016-4001-9001-000000000016','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000021',5,'Profesional serio',now()-'17 days'::interval),
 ('30010000-1008-4001-9003-000000000008','10010000-1006-4001-9001-000000000006','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000022',4,'Fuga sellada',now()-'6 days'::interval),
 ('30010000-1009-4001-9003-000000000009','10010000-1010-4001-9001-000000000010','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000022',4,'Bomba reemplazada',now()-'10 days'::interval),
 ('30010000-1010-4001-9003-000000000010','10010000-1014-4001-9001-000000000014','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000022',5,'Rápido y limpio',now()-'15 days'::interval),
 ('30010000-1011-4001-9003-000000000011','10010000-1018-4001-9001-000000000018','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000022',4,'Trabajo fino',now()-'18 days'::interval),
 ('30010000-1012-4001-9003-000000000012','10010000-1012-4001-9001-000000000012','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000023',5,'HVAC impecable',now()-'11 days'::interval),
 ('30010000-1013-4001-9003-000000000013','10010000-1020-4001-9001-000000000020','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000023',5,'Máquina en marcha',now()-'22 days'::interval);

-- ------------------------------------------------------------
-- 12) REVIEW_VALIDATIONS  (v001..v013)
--   Ana: 4 approved / 1 needs_revision (j005)
--   Luis: 2 approved
--   Carlos: 3 approved
--   Diana: 3 approved (first-time-fix)
-- ------------------------------------------------------------
INSERT INTO review_validations (id,job_id,supervisor_id,status,score,notes,validated_at)
VALUES
 ('40010000-1001-4001-9004-000000000001','10010000-1001-4001-9001-000000000001','a0000000-0000-0000-0000-000000000002','approved',9.5,'Trabajo impecable',now()-'2 days'::interval),
 ('40010000-1002-4001-9004-000000000002','10010000-1005-4001-9001-000000000005','a0000000-0000-0000-0000-000000000002','needs_revision',7.0,'Revisar documentación',now()-'7 days'::interval),
 ('40010000-1003-4001-9004-000000000003','10010000-1009-4001-9001-000000000009','a0000000-0000-0000-0000-000000000002','approved',9.0,'OK',now()-'12 days'::interval),
 ('40010000-1004-4001-9004-000000000004','10010000-1013-4001-9001-000000000013','a0000000-0000-0000-0000-000000000002','approved',9.2,'OK',now()-'16 days'::interval),
 ('40010000-1005-4001-9004-000000000005','10010000-1017-4001-9001-000000000017','a0000000-0000-0000-0000-000000000002','approved',9.8,'Excelente',now()-'20 days'::interval),
 ('40010000-1006-4001-9004-000000000006','10010000-1008-4001-9001-000000000008','a0000000-0000-0000-0000-000000000002','approved',8.5,'OK',now()-'8 days'::interval),
 ('40010000-1007-4001-9004-000000000007','10010000-1016-4001-9001-000000000016','a0000000-0000-0000-0000-000000000002','approved',9.0,'OK',now()-'17 days'::interval),
 ('40010000-1008-4001-9004-000000000008','10010000-1006-4001-9001-000000000006','a0000000-0000-0000-0000-000000000002','approved',8.8,'OK',now()-'6 days'::interval),
 ('40010000-1009-4001-9004-000000000009','10010000-1010-4001-9001-000000000010','a0000000-0000-0000-0000-000000000002','approved',8.6,'OK',now()-'10 days'::interval),
 ('40010000-1010-4001-9004-000000000010','10010000-1014-4001-9001-000000000014','a0000000-0000-0000-0000-000000000002','approved',9.4,'OK',now()-'15 days'::interval),
 ('40010000-1011-4001-9004-000000000011','10010000-1018-4001-9001-000000000018','a0000000-0000-0000-0000-000000000002','approved',9.1,'OK',now()-'18 days'::interval),
 ('40010000-1012-4001-9004-000000000012','10010000-1012-4001-9001-000000000012','a0000000-0000-0000-0000-000000000002','approved',9.6,'Impecable',now()-'11 days'::interval),
 ('40010000-1013-4001-9004-000000000013','10010000-1020-4001-9001-000000000020','a0000000-0000-0000-0000-000000000002','approved',9.7,'OK',now()-'22 days'::interval);

-- ------------------------------------------------------------
-- 13) PAYMENTS (p001..p013)  solo jobs COMPLETED; IT 12%, resto 15%
--  La comisión de plataforma = amount * rate_pct
-- ------------------------------------------------------------
INSERT INTO payments (id,job_id,payer_id,payee_id,amount,currency,method,status,provider_txn_id,created_at,updated_at)
VALUES
 ('20010000-1001-4001-9002-000000000001','10010000-1001-4001-9001-000000000001','a0000000-0000-0000-0000-000000000010','a0000000-0000-0000-0000-000000000020',500,'USD','card','succeeded','txn_001',now()-'3 days'::interval,now()-'3 days'::interval),
 ('20010000-1002-4001-9002-000000000002','10010000-1005-4001-9001-000000000005','a0000000-0000-0000-0000-000000000010','a0000000-0000-0000-0000-000000000023',1350,'USD','card','succeeded','txn_002',now()-'8 days'::interval,now()-'8 days'::interval),
 ('20010000-1003-4001-9002-000000000003','10010000-1009-4001-9001-000000000009','a0000000-0000-0000-0000-000000000010','a0000000-0000-0000-0000-000000000020',650,'USD','transfer','succeeded','txn_003',now()-'13 days'::interval,now()-'13 days'::interval),
 ('20010000-1004-4001-9002-000000000004','10010000-1013-4001-9001-000000000013','a0000000-0000-0000-0000-000000000010','a0000000-0000-0000-0000-000000000020',750,'USD','card','succeeded','txn_005',now()-'16 days'::interval,now()-'16 days'::interval),
 ('20010000-1005-4001-9002-000000000005','10010000-1017-4001-9001-000000000017','a0000000-0000-0000-0000-000000000010','a0000000-0000-0000-0000-000000000020',1100,'USD','card','succeeded','txn_006',now()-'20 days'::interval,now()-'20 days'::interval),
 ('20010000-1006-4001-9002-000000000006','10010000-1008-4001-9001-000000000008','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000021',1100,'USD','transfer','succeeded','txn_007',now()-'9 days'::interval,now()-'9 days'::interval),
 ('20010000-1007-4001-9002-000000000007','10010000-1016-4001-9001-000000000016','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000021',1300,'USD','card','succeeded','txn_008',now()-'17 days'::interval,now()-'17 days'::interval),
 ('20010000-1008-4001-9002-000000000008','10010000-1006-4001-9001-000000000006','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000022',450,'USD','card','succeeded','txn_009',now()-'6 days'::interval,now()-'6 days'::interval),
 ('20010000-1009-4001-9002-000000000009','10010000-1010-4001-9001-000000000010','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000022',600,'USD','card','succeeded','txn_010',now()-'10 days'::interval,now()-'10 days'::interval),
 ('20010000-1010-4001-9002-000000000010','10010000-1014-4001-9001-000000000014','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000022',220,'USD','wallet','succeeded','txn_011',now()-'15 days'::interval,now()-'15 days'::interval),
 ('20010000-1011-4001-9002-000000000011','10010000-1018-4001-9001-000000000018','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000022',300,'USD','transfer','succeeded','txn_012',now()-'18 days'::interval,now()-'18 days'::interval),
 ('20010000-1012-4001-9002-000000000012','10010000-1012-4001-9001-000000000012','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000023',1500,'USD','card','succeeded','txn_013',now()-'11 days'::interval,now()-'11 days'::interval),
 ('20010000-1013-4001-9002-000000000013','10010000-1020-4001-9001-000000000020','a0000000-0000-0000-0000-000000000011','a0000000-0000-0000-0000-000000000023',2800,'USD','transfer','succeeded','txn_014',now()-'22 days'::interval,now()-'22 days'::interval);

-- ------------------------------------------------------------
-- 14) DOCUMENTS (evidencias fotos)
-- ------------------------------------------------------------
INSERT INTO documents (id,job_id,uploader_id,type,url,file_name,file_size_bytes,mime_type,created_at)
VALUES
 ('50010000-0001-4001-9005-000000000001','10010000-1001-4001-9001-000000000001','a0000000-0000-0000-0000-000000000020','evidence','https://s3/j001_ev.jpg','antes.jpg',120000,'image/jpeg',now()-'3 days'::interval),
 ('50010000-0002-4001-9005-000000000002','10010000-1005-4001-9001-000000000005','a0000000-0000-0000-0000-000000000023','work_photo','https://s3/j005_wf.jpg','cableado.jpg',240000,'image/jpeg',now()-'8 days'::interval),
 ('50010000-0003-4001-9005-000000000003','10010000-1004-4001-9001-000000000004','a0000000-0000-0000-0000-000000000023','evidence','https://s3/j004_ev.jpg','HVAC.jpg',180000,'image/jpeg',now()-'2 days'::interval);

-- ------------------------------------------------------------
-- 15) NOTIFICATIONS  (generan DAU simulada; `read` es keyword -> comilla doble)
-- ------------------------------------------------------------
INSERT INTO notifications (id,user_id,title,message,type,reference_id,created_at,"read")
VALUES
 ('70010000-1001-4001-9007-000000000001','a0000000-0000-0000-0000-000000000020','Nueva oferta','Solicitud j019','job_applied','10010000-1019-4001-9001-000000000019',now()-'1 day'::interval,FALSE),
 ('70010000-1002-4001-9007-000000000002','a0000000-0000-0000-0000-000000000023','Nueva oferta','Solicitud j004','job_applied','10010000-1004-4001-9001-000000000004',now()-'1 day'::interval,FALSE),
 ('70010000-1003-4001-9007-000000000003','a0000000-0000-0000-0000-000000000021','Nueva oferta','Solicitud en Chueca','job_applied','10010000-1016-4001-9001-000000000016',now()-'1 day'::interval,FALSE),
 ('70010000-1004-4001-9007-000000000004','a0000000-0000-0000-0000-000000000022','Nueva oferta','Fuga agua urgente','job_applied','10010000-1014-4001-9001-000000000014',now()-'2 days'::interval,FALSE),
 ('70010000-1005-4001-9007-000000000005','a0000000-0000-0000-0000-000000000010','Trabajo completado','j001 finalizado y validado','job_completed','10010000-1001-4001-9001-000000000001',now()-'2 days'::interval,TRUE),
 ('70010000-1006-4001-9007-000000000006','a0000000-0000-0000-0000-000000000011','Pago recibido','j006 pagado','payment','20010000-1008-4001-9002-000000000008',now()-'5 days'::interval,FALSE),
 ('70010000-1007-4001-9007-000000000007','a0000000-0000-0000-0000-000000000020','Reseña nueva','Tu rating: 5.0','review_added','30010000-1001-4001-9003-000000000001',now()-'2 days'::interval,FALSE),
 ('70010000-1008-4001-9007-000000000008','a0000000-0000-0000-0000-000000000023','Trabajo asignado','j020 asignado','job_assigned','10010000-1020-4001-9001-000000000020',now()-'21 days'::interval,TRUE),
 ('70010000-1009-4001-9007-000000000009','a0000000-0000-0000-0000-000000000010','Pago recibido','j005 pagado','payment','20010000-1002-4001-9002-000000000002',now()-'7 days'::interval,FALSE),
 ('70010000-1010-4001-9007-000000000010','a0000000-0000-0000-0000-000000000022','Reseña nueva','Tu rating: 4.0','review_added','30010000-1008-4001-9003-000000000008',now()-'6 days'::interval,FALSE),
 ('70010000-1011-4001-9007-000000000011','a0000000-0000-0000-0000-000000000011','Trabajo completado','j020 finalizado','job_completed','10010000-1020-4001-9001-000000000020',now()-'22 days'::interval,FALSE),
 ('70010000-1012-4001-9007-000000000012','a0000000-0000-0000-0000-000000000021','Validación completada','j016 aprobado','system','40010000-1007-4001-9004-000000000007',now()-'16 days'::interval,FALSE));

-- ------------------------------------------------------------
-- 16) KPI_SNAPSHOTS semanales iniciales (histórico)
--  Primero se refresca la MV con todos los datos insertados, para que
--  estos inserts lean valores reales (no la MV vacía de schema.sql).
-- ------------------------------------------------------------
REFRESH MATERIALIZED VIEW mv_platform_metrics;

INSERT INTO kpi_snapshots(entity_type,entity_id,metric_name,metric_value,period_start,period_end)
SELECT 'platform',NULL,'jobs_created_weekly',jobs_created,wk,wk+6
FROM   mv_platform_metrics;
INSERT INTO kpi_snapshots(entity_type,entity_id,metric_name,metric_value,period_start,period_end)
SELECT 'platform',NULL,'completion_rate',completion_rate,wk,wk+6
FROM   mv_platform_metrics;
INSERT INTO kpi_snapshots(entity_type,entity_id,metric_name,metric_value,period_start,period_end)
SELECT 'platform',NULL,'gmv',gmv,wk,wk+6
FROM   mv_platform_metrics;
INSERT INTO kpi_snapshots(entity_type,entity_id,metric_name,metric_value,period_start,period_end)
SELECT 'platform',NULL,'revenue',revenue,wk,wk+6
FROM   mv_platform_metrics;

-- KPIs por técnico (histórico snapshot)
INSERT INTO kpi_snapshots(entity_type,entity_id,metric_name,metric_value,period_start,period_end)
SELECT 'technician',u.id,'rating',tm.avg_rating,CURRENT_DATE-'6 days',CURRENT_DATE
FROM users u JOIN v_tech_metrics tm ON tm.technician_id=u.id WHERE u.role='technician';
INSERT INTO kpi_snapshots(entity_type,entity_id,metric_name,metric_value,period_start,period_end)
SELECT 'technician',u.id,'earnings',tm.total_earned,CURRENT_DATE-'6 days',CURRENT_DATE
FROM users u JOIN v_tech_metrics tm ON tm.technician_id=u.id WHERE u.role='technician';

-- (la MV ya fue refrescada arriba; snapshots históricos poblados)
\echo 'SEED COMPLETE: 8 users (1 admin, 1 supervisor, 2 clientes, 4 técnicos), 4 specialties, 1 cert vencida, 20 jobs (14 completed, 4 in_progress, 3 cancelled), 8 applications, 22 assignments (16 accepted / 6 rejected), 13 reviews, 13 validaciones, 13 pagos, 3 docs, 12 notis. KPIs listos en mv_platform_metrics + views.'
