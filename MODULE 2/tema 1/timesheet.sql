-- Creare baza de date in locatie specifica 
use master;
go


drop database if exists Pontaj;   
go

exec master.dbo.xp_create_subdir 'C:\SQL_Database';  
go

create database Pontaj
on primary (
    name = 'Pontaj_Data',
    filename = 'C:\SQL_Database\Pontaj_Data.mdf',
    size = 50mb,
    filegrowth = 20mb
)
log on (
    name = 'Pontaj_Log',
    filename = 'C:\SQL_Database\Pontaj_Log.ldf',
    size = 50mb,
    filegrowth = 50mb
);
go

-- Filegroup separat pentru indecsi
alter database Pontaj add filegroup FG_Index;

alter database Pontaj
add file (name = 'Pontaj_Index', filename = 'C:\SQL_Database\Pontaj_Index.ndf')
  to filegroup FG_Index;
go

use Pontaj;
go



create schema hr;
go
create schema ts;
go



--Constrangeri: 

-- PK simplu             -> hr.Departament.departament_id
-- PK compus             -> hr.AlocareProiect (angajat_id, proiect_id)
-- FOREIGN KEY           -> hr.Angajat.departament_id spre hr.Departament
-- FK spre acelasi tabel -> hr.Angajat.manager_id spre hr.Angajat (EXTRA) un manager e tot un angajat
-- NOT NULL              -> hr.Departament.nume
-- CHECK pe valoare      -> ts.Pontaj.ore (>0 si <=24) si data_pontaj <= getdate()
-- CHECK cu functie      -> hr.Angajat.detalii cu isjson(...)=1         
-- DEFAULT               -> hr.Angajat.status = 'ACTIV'                    
-- IDENTITY              -> toate cheile _id (auto-increment)             
-- UNIQUE                -> hr.Departament.cod (EXTRA)
-- Data-in-viitor = Check regulile intre tabele + totalul zilei <= norma = trigger

create table hr.Departament (
    departament_id int identity(1,1) primary key, -- PK simplu + identity
    cod  varchar(10) not null unique, -- UNIQUE + NOT NULL
    nume nvarchar(100) not null
);
go

create table hr.Angajat (
    angajat_id int identity(1,1) primary key,
    nume  nvarchar(100) not null,
    email varchar(150) not null unique check (email like '%_@_%._%'),  
    departament_id int not null,
    manager_id int null,
    data_angajarii date not null default cast(getdate() as date),      
    salariu_orar decimal(8,2) not null check (salariu_orar > 0),      
    norma_zilnica tinyint not null default 8 check (norma_zilnica in (4,6,8)),
    status varchar(10) not null default 'ACTIV' check (status in ('ACTIV','INACTIV','CONCEDIU')),
    detalii nvarchar(max) null check (detalii is null or isjson(detalii) = 1), 
    foreign key (departament_id) references hr.Departament(departament_id),
    foreign key (manager_id) references hr.Angajat(angajat_id),          
    constraint ck_angajat_manager check (manager_id <> angajat_id) -- nu poti fi propriul manager
);
go

create table hr.Proiect (
    proiect_id int identity(1,1) primary key,
    cod  varchar(20) not null unique,
    nume nvarchar(150) not null,
    data_start date not null,
    data_end   date null,
    buget decimal(12,2) null check (buget is null or buget >= 0),
    client_info xml null,  
    check (data_end is null or data_end >= data_start) 
);
go

create table hr.TipActivitate (
    tip_id int identity(1,1) primary key,
    cod  varchar(20) not null unique,
    nume nvarchar(100) not null,
    facturabil bit not null default 1
);
go

create table hr.AlocareProiect (
    angajat_id int not null,
    proiect_id int not null,
    data_alocare date not null default cast(getdate() as date),
    procent_alocare tinyint not null default 100 check (procent_alocare between 1 and 100),
    primary key (angajat_id, proiect_id), -- PK compus
    foreign key (angajat_id) references hr.Angajat(angajat_id),
    foreign key (proiect_id) references hr.Proiect(proiect_id)
);
go

create table ts.Pontaj (
    pontaj_id bigint identity(1,1) primary key,
    angajat_id int not null,
    proiect_id int not null,
    tip_id int not null,
    data_pontaj date not null check (data_pontaj <= getdate()), -- fara date in viitor (CK)
    ore decimal(4,2) not null check (ore > 0 and ore <= 24),
    descriere nvarchar(500) null,
    aprobat char(1) not null default 'N' check (aprobat in ('D','N')),
    metadata nvarchar(max) null check (metadata is null or isjson(metadata) = 1), 
    unique (angajat_id, proiect_id, tip_id, data_pontaj), -- un singur pontaj / tip / zi
    foreign key (angajat_id, proiect_id) references hr.AlocareProiect(angajat_id, proiect_id),
    foreign key (tip_id) references hr.TipActivitate(tip_id)
);
go


-- Indecsi 
-- nonclustered pt ca indexul clustered e chiar ordinea fizica a randurilor si e deja ocupat de cheia primara ( deci max 1)
create nonclustered index IX_Pontaj_Data on ts.Pontaj(data_pontaj) on FG_Index; -- pe filegroup separat
create nonclustered index IX_Angajat_Nume on hr.Angajat(nume);
go


-- Trigger cu regulile de business pentru pontaj
--  A) data pontajului >= data angajarii (nu poti ponta inainte sa fii angajat)
--  B) data pontajului sa fie in perioada proiectului (data_start .. data_end)
--  C) doar angajatii cu status ACTIV pot ponta
--  D) pontaj doar in zile lucratoare (fara weekend)
--  E) TOTALUL orelor dintr-o zi <= norma zilnica a angajatului
-- Alte reguli de business, in afara acestui trigger:
-- pontaj doar pe proiect alocat = FK compusa spre hr.AlocareProiect
-- alocare totala <= 100% = trigger separat pe hr.AlocareProiect
-- nu poti fi propriul manager= CHECK (ck_angajat_manager)

create or alter trigger ts.trg_Pontaj_Validari
on ts.Pontaj
after insert, update
as
begin
    set nocount on;

    -- A) pontaj inaintea datei de angajare
    if exists (
        select 1 from inserted i
        join hr.Angajat a on a.angajat_id = i.angajat_id
        where i.data_pontaj < a.data_angajarii
    )
    begin
        raiserror('Pontajul nu poate fi inaintea datei de angajare a angajatului.', 16, 1);
        rollback transaction; return;
    end

    -- B) pontaj in afara perioadei proiectului
    if exists (
        select 1 from inserted i
        join hr.Proiect p on p.proiect_id = i.proiect_id
        where i.data_pontaj < p.data_start
           or (p.data_end is not null and i.data_pontaj > p.data_end)
    )
    begin
        raiserror('Pontajul trebuie sa fie in perioada proiectului (data_start .. data_end).', 16, 1);
        rollback transaction; return;
    end

    -- C) angajat inactiv / in concediu nu poate ponta
    if exists (
        select 1 from inserted i
        join hr.Angajat a on a.angajat_id = i.angajat_id
        where a.status <> 'ACTIV'
    )
    begin
        raiserror('Doar angajatii cu status ACTIV pot ponta.', 16, 1);
        rollback transaction; return;
    end

    -- D) pontaj doar in zile lucratoare (fara weekend)
    if exists (
        select 1 from inserted i
        where datediff(day, 0, i.data_pontaj) % 7 in (5, 6)   -- 5 = sambata, 6 = duminica
    )
    begin
        raiserror('Pontajul se poate face doar in zile lucratoare (fara weekend).', 16, 1);
        rollback transaction; return;
    end

    -- E) totalul orelor dintr-o zi nu poate depasi norma zilnica a angajatului
    if exists (
        select 1
        from (select distinct angajat_id, data_pontaj from inserted) k
        join hr.Angajat a on a.angajat_id = k.angajat_id
        cross apply (
            select sum(p.ore) as tot from ts.Pontaj p
            where p.angajat_id = k.angajat_id and p.data_pontaj = k.data_pontaj
        ) s
        where s.tot > a.norma_zilnica
    )
    begin
        raiserror('Totalul orelor pontate intr-o zi nu poate depasi norma zilnica a angajatului.', 16, 1);
        rollback transaction; return;
    end
end;
go

-- Trigger separat - alocarea totala a unui angajat pe proiecte nu poate depasi 100%
create or alter trigger hr.trg_Alocare_Procent
on hr.AlocareProiect
after insert, update
as
begin
    set nocount on;
    if exists (
        select 1 from hr.AlocareProiect
        where angajat_id in (select angajat_id from inserted)
        group by angajat_id
        having sum(procent_alocare) > 100
    )
    begin
        raiserror('Alocarea totala a unui angajat nu poate depasi 100%%.', 16, 1);
        rollback transaction;
    end
end;
go


-- Populare date

insert into hr.Departament (cod, nume) values
    ('IT',  N'Tehnologie'),
    ('HR',  N'Resurse Umane'),
    ('FIN', N'Financiar'),
    ('OPS', N'Operatiuni');
go

insert into hr.TipActivitate (cod, nume, facturabil) values
    ('DEV', N'Development', 1),
    ('TEST',N'Testing', 1),
    ('MTG', N'Meeting', 0),
    ('DOC', N'Documentation', 1),
    ('SUP', N'Support', 1),
    ('CO', N'Concediu', 0);
go

insert into hr.Proiect (cod, nume, data_start, data_end, buget, client_info) values
    ('PRJ-001', N'Migrare ERP', '2024-01-15', null, 250000, N'<client nume="Alpha SRL"><contact email="office@alpha.ro" telefon="0211111111"/><tara>RO</tara></client>'),
    ('PRJ-002', N'Portal Clienti', '2024-03-01', null, 180000, N'<client nume="Beta SA"><contact email="it@beta.com" telefon="0212222222"/><tara>RO</tara></client>'),
    ('PRJ-003', N'App Mobila', '2024-05-10', null, 320000, N'<client nume="Gamma GmbH"><contact email="dev@gamma.de" telefon="0049301234"/><tara>DE</tara></client>'),
    ('PRJ-004', N'Raportare BI', '2024-02-20', dateadd(day,-45,cast(getdate() as date)),  95000, N'<client nume="Delta Ltd"><contact email="bi@delta.co.uk" telefon="0044201234"/><tara>UK</tara></client>'),
    ('PRJ-005', N'Integrare Plati', '2024-06-01', null, 210000, N'<client nume="Epsilon SRL"><contact email="pay@epsilon.ro" telefon="0213333333"/><tara>RO</tara></client>'),
    ('PRJ-006', N'Data Warehouse', '2024-04-05', null, 400000, N'<client nume="Zeta Inc"><contact email="data@zeta.com" telefon="0015551234"/><tara>US</tara></client>'),
    ('PRJ-007', N'Automatizari RPA','2024-07-01', null, 150000, N'<client nume="Eta SRL"><contact email="rpa@eta.ro" telefon="0214444444"/><tara>RO</tara></client>'),
    ('PRJ-008', N'Securitate Audit','2024-03-15', null, 130000, N'<client nume="Theta SA"><contact email="sec@theta.ro" telefon="0215555555"/><tara>RO</tara></client>'),
    ('PRJ-009', N'Proiect Nou', '2025-06-01', null, 60000, N'<client nume="Iota SRL"><contact email="new@iota.ro" telefon="0216666666"/><tara>RO</tara></client>');
go



insert into hr.Angajat (nume, email, departament_id, data_angajarii, salariu_orar, norma_zilnica, status, detalii)
select top (24)
    concat(N'Angajat_', n),
    concat('angajat', n, '@firma.ro'),
    ((n - 1) % 4) + 1,
    dateadd(day, -(n * 25), cast(getdate() as date)),
    cast(50 + (n % 30) as decimal(8,2)),
    case when n % 7 = 0 then 6 else 8 end,
    case when n % 11 = 0 then 'CONCEDIU' else 'ACTIV' end,
    concat(N'{"skilluri":["SQL","', case when n % 2 = 0 then N'CSharp' else N'Java' end,
           N'"],"telefon":"0700', right(concat('000', n), 3),
           N'","remote":', case when n % 3 = 0 then N'true' else N'false' end, N'}')
from (select row_number() over (order by (select null)) as n from sys.all_objects) t;
go

-- Ce iese, pe fiecare camp (n = 1 -> 24):
-- angajat_id      -> 1..24 
-- nume            -> Angajat_1 .. Angajat_24
-- email           -> angajat1@firma.ro .. angajat24@firma.ro
-- departament_id  -> cicleaza 1,2,3,4 (cate 6 angajati pe departament)
-- manager_id      -> NULL la id 1 (radacina); restul = id/2 -> 1..12 (arbore de manageri)
-- data_angajarii  -> azi - n*25 zile: de la azi-25 (n=1, cel mai nou) la azi-600 (n=24, cel mai vechi)
-- salariu_orar    -> 51.00 -> 74.00 / ora
-- norma_zilnica   -> 6 pentru n=7,14,21 (3 angajati); 8 in rest (21 angajati)
-- status          -> CONCEDIU pentru n=11,22 (2 angajati); ACTIV in rest (22 angajati)
-- detalii (JSON)  -> skill: CSharp daca n e par, altfel Java (12/12) | telefon: 0700001 -> 0700024
-- remote: true daca n%3=0 (8 angajati), altfel false (16)


-- fiecare raporteaza la id/2, rezulta un arbore de manageri 
update hr.Angajat set manager_id = angajat_id / 2 where angajat_id > 1;
go

-- alocari: fiecare angajat pe 2 proiecte consecutive (ciclic prin cele 8), 50% fiecare => 100% total
-- ex: angajatul 2 -> proiectele 2,3; angajatul 8 -> proiectele 8,1 
-- nu poti aloca pe cineva pe un proiect inainte sa existe amandoua
insert into hr.AlocareProiect (angajat_id, proiect_id, data_alocare, procent_alocare)
select x.angajat_id, x.proiect_id,
       case when e.data_angajarii > pr.data_start then e.data_angajarii else pr.data_start end,
       50
from (
    select a.angajat_id, ((a.angajat_id - 1) % 8) + 1 as proiect_id from hr.Angajat a
    union
    select a.angajat_id, (a.angajat_id % 8) + 1 as proiect_id from hr.Angajat a
) x
join hr.Angajat e  on e.angajat_id = x.angajat_id
join hr.Proiect pr on pr.proiect_id = x.proiect_id;
go



-- Ce iese pe fiecare camp:
--   angajat_id  -> doar angajati activi (cei in concediu nu apar)
--   proiect_id  -> un proiect alocat si activ in ziua z (ales aleator din cele 2 ale lui)
--   tip_id      -> 1 din cele 5 tipuri fara Concediu (tip de activitate) 
--   data_pontaj -> zi lucratoare, din ultimele 120 de zile, doar >= data angajarii
--   ore         -> norma-1 sau norma-2 (ex. 8 -> 6/7): mereu sub norma zilnica
--   descriere   -> "Activitate: " + numele tipului (ex. "Activitate: Meeting")
--   aprobat     -> D daca ziua e mai veche de 2 saptamani, altfel N (recent = in asteptare)
--   metadata    -> JSON {..."facturabil":...}: facturabil vine din tipul ales

insert into ts.Pontaj (angajat_id, proiect_id, tip_id, data_pontaj, ore, descriere, aprobat, metadata)
select
    e.angajat_id,
    ap.proiect_id, -- proiect alocat + activ in ziua z
    tp.tip_id, -- tipul ales o singura data 
    z.zi,
    cast(e.norma_zilnica - 1 - abs(checksum(newid()) % 2) as decimal(4,2)),  
    concat(N'Activitate: ', tp.nume), 
    case when z.zi < dateadd(day, -14, cast(getdate() as date)) then 'D' else 'N' end,
    concat(N'{"locatie":"birou","facturabil":',
           case when tp.facturabil = 1 then N'true' else N'false' end, N'}')
from hr.Angajat e
join (
    select cast(dateadd(day, -(row_number() over (order by (select null)) - 1), cast(getdate() as date)) as date) as zi
    from (select top (120) 1 as x from sys.all_objects) d
) z on (datediff(day, 0, z.zi) % 7) not in (5, 6)
cross apply (                               
    select top (1) al.proiect_id
    from hr.AlocareProiect al
    join hr.Proiect pr on pr.proiect_id = al.proiect_id
    where al.angajat_id = e.angajat_id
      and z.zi >= pr.data_start
      and (pr.data_end is null or z.zi <= pr.data_end)
    order by newid()
) ap
cross apply (                                         
    select tp2.tip_id, tp2.nume, tp2.facturabil       
    from (select t.tip_id, t.nume, t.facturabil,
                 row_number() over (order by t.tip_id) as rn
          from hr.TipActivitate t
          where t.cod <> 'CO') tp2 -- concediul nu se ponteaza pe proiect
    where tp2.rn = ((e.angajat_id + datediff(day, 0, z.zi)) % 5) + 1
) tp
where e.status = 'ACTIV'
  and z.zi >= e.data_angajarii;                            
go


-- View-uri

-- cerinta 4: view
-- sumar ore pe angajat, cu LEFT JOIN ca sa apara si cei fara pontaje (cu 0) 
create or alter view ts.View_AngajatiOre as
select e.angajat_id, e.nume, d.nume as departament,
       count(p.pontaj_id) as nr_pontaje,
       isnull(sum(p.ore), 0) as total_ore
from hr.Angajat e
join hr.Departament d on d.departament_id = e.departament_id
left join ts.Pontaj p on p.angajat_id = e.angajat_id
group by e.angajat_id, e.nume, d.nume;
go


select * from ts.View_AngajatiOre order by total_ore desc;
go


-- cerinta 4: al doilea view
-- ore lunare pe proiect (cate ore pe fiecare luna) 
create or alter view ts.View_OreLunareProiect as
select pr.cod as cod_proiect, pr.nume as proiect,
       year(p.data_pontaj) as an, month(p.data_pontaj) as luna,
       sum(p.ore) as total_ore
from ts.Pontaj p
join hr.Proiect pr on pr.proiect_id = p.proiect_id
group by pr.cod, pr.nume, year(p.data_pontaj), month(p.data_pontaj);
go


select * from ts.View_OreLunareProiect order by cod_proiect, an, luna;
go



-- cerinta 5 view   
-- Pentru fiecare pereche (proiect, angajat): cate ore a lucrat in total acolo si din cate pontaje.
create view ts.View_Materializat_OreProiect
with schemabinding
as
select p.proiect_id, p.angajat_id,
       sum(p.ore) as total_ore,
       count_big(*) as nr_pontaje
from ts.Pontaj p
group by p.proiect_id, p.angajat_id;
go

create unique clustered index IX_View_Materializat
on ts.View_Materializat_OreProiect(proiect_id, angajat_id);
go


select * from ts.View_Materializat_OreProiect order by proiect_id, angajat_id;
go



-- cerinta 6
-- Pentru fiecare angajat si fiecare luna: cate ore a lucrat in total - dar doar lunile cu peste 100 de ore.
select e.nume, year(p.data_pontaj) as an, month(p.data_pontaj) as luna, sum(p.ore) as total_ore
from ts.Pontaj p
join hr.Angajat e on e.angajat_id = p.angajat_id
group by e.nume, year(p.data_pontaj), month(p.data_pontaj)
having sum(p.ore) > 100
order by e.nume, an, luna;
go


-- cerinta 7
-- Toate cele 9 proiecte cu orele lucrate pe fiecare, sortate descrescator
-- left join pentru a aparea si proiectele fara pontaje 
select pr.cod, pr.nume,
       count(p.pontaj_id) as nr_pontaje,
       isnull(sum(p.ore), 0) as total_ore
from hr.Proiect pr
left join ts.Pontaj p on p.proiect_id = pr.proiect_id
group by pr.cod, pr.nume
order by total_ore desc;
go

-- cerinta 8 
-- pentru fiecare angajat si luna - orele lucrate si pe ce loc e in clasamentul lunii aceleia.
select e.nume, year(p.data_pontaj) as an, month(p.data_pontaj) as luna, sum(p.ore) as ore_luna,
       rank() over (partition by year(p.data_pontaj), month(p.data_pontaj) order by sum(p.ore) desc) as loc_in_luna
from ts.Pontaj p
join hr.Angajat e on e.angajat_id = p.angajat_id
group by e.nume, year(p.data_pontaj), month(p.data_pontaj)
order by an, luna, loc_in_luna;
go


-- pentru fiecare angajat si luna - orele lunii, orele lunii precedente si diferenta dintre ele
with lunar as (
    select p.angajat_id, year(p.data_pontaj) as an, month(p.data_pontaj) as luna, sum(p.ore) as ore_luna
    from ts.Pontaj p
    group by p.angajat_id, year(p.data_pontaj), month(p.data_pontaj)
)
select angajat_id, an, luna, ore_luna,
       lag(ore_luna) over (partition by angajat_id order by an, luna) as ore_luna_trecuta,
       ore_luna - lag(ore_luna) over (partition by angajat_id order by an, luna) as diferenta
from lunar
order by angajat_id, an, luna;
go


-- cerinta 2
-- scot telefonul si remote din coloana detalii 
select e.nume,
       json_value(e.detalii, '$.telefon') as telefon,
       json_value(e.detalii, '$.remote')  as remote
from hr.Angajat e;
go

-- cerinta 2 
-- desfac array-ul de skilluri in randuri 
select e.nume, s.[value] as skill
from hr.Angajat e
cross apply openjson(e.detalii, '$.skilluri') s
order by e.nume, skill;
go

-- cerinta 2 
-- scot numele clientului, email si tara din coloana client_info 
select pr.cod, pr.nume,
       pr.client_info.value('(/client/@nume)[1]', 'nvarchar(100)') as client,
       pr.client_info.value('(/client/contact/@email)[1]', 'varchar(150)') as email_client,
       pr.client_info.value('(/client/tara)[1]', 'varchar(5)') as tara
from hr.Proiect pr
where pr.client_info is not null;
go







-- Test constrangeri 

-- nu poti ponta o zi care n-a venit inca
begin try
    insert into ts.Pontaj (angajat_id, proiect_id, tip_id, data_pontaj, ore)
    values (1, 1, 1, '2099-01-01', 5);  -- data in viitor
end try begin catch
    print 'OK - CK data_pontaj a respins data din viitor: ' + error_message();
end catch
go

-- o zi are maximum 24 de ore
begin try
    insert into ts.Pontaj (angajat_id, proiect_id, tip_id, data_pontaj, ore)
    values (1, 2, 6, cast(getdate() as date), 30);      -- 30 ore, peste limita CK (ore <= 24)
end try begin catch
    print 'OK - CK ore a respins 30 de ore: ' + error_message();
end catch
go


-- coloana JSON accepta doar JSON valid, nu orice text
begin try
    insert into hr.Angajat (nume, email, departament_id, salariu_orar, detalii)
    values (N'Test', 'test@firma.ro', 1, 10, N'nu sunt json');   -- JSON invalid
end try begin catch
    print 'OK - CK isjson a respins textul care nu e JSON: ' + error_message();
end catch
go



-- Test reguli de business. Fiecare insert e gresit intentionat si trebuie respins; il prind cu
-- try/catch ca sa nu opreasca scriptul.

-- A) pontaj inaintea datei de angajare
begin try
    insert into ts.Pontaj (angajat_id, proiect_id, tip_id, data_pontaj, ore)
    values (1, 1, 1, '2000-01-01', 5);
    print 'ATENTIE: regula A NU a respins!';
end try begin catch
    print 'OK - A: pontaj inainte de angajare respins: ' + error_message();
end catch
go

-- B) pontaj in afara perioadei proiectului (PRJ-004 e deja terminat)
begin try
    insert into ts.Pontaj (angajat_id, proiect_id, tip_id, data_pontaj, ore)
    values (3, 4, 1, cast(getdate() as date), 5);
    print 'ATENTIE: regula B NU a respins!';
end try begin catch
    print 'OK - B: pontaj dupa terminarea proiectului respins: ' + error_message();
end catch
go

-- C) angajat non-ACTIV (angajatul 11 e in CONCEDIU; e alocat pe proiectul 3 si proiectul e activ azi,
--    deci trece de FK si de regula B si ajunge chiar la verificarea de status)
begin try
    insert into ts.Pontaj (angajat_id, proiect_id, tip_id, data_pontaj, ore)
    values (11, 3, 1, cast(getdate() as date), 5);
    print 'ATENTIE: regula C NU a respins!';
end try begin catch
    print 'OK - C: pontaj de la angajat non-ACTIV respins: ' + error_message();
end catch
go

-- D) pontaj in weekend
begin try
    declare @we date = dateadd(day, -((datediff(day, 0, cast(getdate() as date)) - 5 + 7) % 7), cast(getdate() as date)); -- ultima sambata
    insert into ts.Pontaj (angajat_id, proiect_id, tip_id, data_pontaj, ore)
    values (1, 1, 1, @we, 5);
    print 'ATENTIE: regula D NU a respins!';
end try begin catch
    print 'OK - D: pontaj in weekend respins: ' + error_message();
end catch
go

-- E) totalul orelor din zi depaseste norma zilnica (angajatul 1 are norma 8, incerc 20h)
begin try
    declare @zi2 date = cast(getdate() as date);
    if datediff(day, 0, @zi2) % 7 = 5 set @zi2 = dateadd(day, -1, @zi2);
    if datediff(day, 0, @zi2) % 7 = 6 set @zi2 = dateadd(day, -2, @zi2);
    insert into ts.Pontaj (angajat_id, proiect_id, tip_id, data_pontaj, ore) values (1, 2, 6, @zi2, 20);
    print 'ATENTIE: regula E NU a respins!';
end try begin catch
    print 'OK - E: total zi peste norma respins: ' + error_message();
end catch
go

-- In afara trigger-ului: FK COMPUSA spre hr.AlocareProiect 
-- pontaj doar pe proiect alocat
-- Angajatul 1 NU e alocat pe proiectul 9 -> respins de cheia straina, nu de trigger.
begin try
    insert into ts.Pontaj (angajat_id, proiect_id, tip_id, data_pontaj, ore)
    values (1, 9, 1, cast(getdate() as date), 5);
    print 'ATENTIE: FK compusa NU a respins!';
end try begin catch
    print 'OK - FK compusa: pontaj pe proiect nealocat respins: ' + error_message();
end catch
go

-- In afara trigger-ului: trg_Alocare_Procent pe hr.AlocareProiect ("suma alocarilor <= 100%").
-- Angajatul 1 are deja 50% + 50%; inca 60% => 160% > 100%.
begin try
    insert into hr.AlocareProiect (angajat_id, proiect_id, procent_alocare)
    values (1, 3, 60);
    print 'ATENTIE: regula de alocare NU a respins!';
end try begin catch
    print 'OK - trg_Alocare_Procent: supra-alocare peste 100% respinsa: ' + error_message();
end catch
go


-- verificare cerinta 1: verificam constrangerile si indecsii 
select name, definition from sys.check_constraints; -- toate CHECK
go

select name, type_desc from sys.key_constraints; -- PK si UNIQUE
go

select object_name(parent_object_id) as pe_tabela, name from sys.foreign_keys; -- FK
go

-- coloanele cu IDENTITY (doar tabelele mele)
select object_name(object_id) as tabela, name as coloana
from sys.columns
where is_identity = 1 and object_name(object_id) in ('Departament','Angajat','Proiect','TipActivitate','Pontaj');
go
