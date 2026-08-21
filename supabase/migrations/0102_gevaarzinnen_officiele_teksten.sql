-- ===========================================================================
-- 0102_gevaarzinnen_officiele_teksten.sql -- de volledige codelijst
-- ===========================================================================
-- Tot nu stonden er vijf gevaarzinnen in de tabel: precies die vijf die een
-- product onder titel 2 van boek VI brengen. Dat was genoeg om de wetgeving te
-- laten werken, maar niet om iets uit te leggen. Van de elf codes in het
-- demodossier had er één een tekst; op de andere tien zei de tooltip "Tekst nog
-- niet in de codelijst". Op een echt product is dat erger dan lelijk: een code
-- zonder tekst is een etiket dat je niet gelezen hebt.
--
-- ---------------------------------------------------------------------------
-- WAAR DE TEKSTEN VANDAAN KOMEN
-- ---------------------------------------------------------------------------
-- Uit de geconsolideerde Nederlandse tekst van verordening (EG) nr. 1272/2008
-- (CLP), versie 01.02.2025, bijlage III -- de lijst van gevarenaanduidingen.
-- Niet uit een samenvatting, niet uit een cursus, niet uit het geheugen: het
-- volledige document is opgehaald bij EUR-Lex en de Nederlandse regel is per
-- code uit de meertalige tabel gehaald.
--
-- Elke rij draagt haar herkomst mee in de kolom bron. Vraagt een klant waar een
-- zin vandaan komt, dan staat het antwoord in de databank en moet niemand het
-- zich herinneren.
--
-- Ter controle is alles vergeleken met de "Lijst van gevarenaanduidingen" van
-- de Vlaamse overheid (departement LNE, versie 1.06.2015). Vier echte
-- verschillen kwamen naar boven, en telkens is de CLP-tekst gevolgd omdat die
-- lijst intussen achterhaald is:
--
--   H314   VL: "Veroorzaakt ernstige brandwonden."
--          CLP: "Veroorzaakt ernstige brandwonden en oogletsel."  <- gevolgd
--   H361   VL: "Wordt ervan verdacht ... te schaden."
--          CLP: "Kan mogelijks ... schaden."                      <- gevolgd
--   H413   VL heeft een tikfout ("schadelijk gevolgen").
--   EUH208 VL laat de naam van de stof weg; CLP houdt die plaats open.
--
-- ---------------------------------------------------------------------------
-- DRIE KEUZES DIE UITLEG VERDIENEN
-- ---------------------------------------------------------------------------
-- 1. Tien aanduidingen bevatten een instructie aan de leverancier in plaats van
--    tekst: H340, H341, H350, H351, H360, H361 en H370 tot H373 dragen
--    "< blootstellingsroute vermelden ... >" of "< betrokken organen vermelden >".
--    Dat is een opdracht aan wie het etiket drukt, geen boodschap aan wie het
--    leest. In tekst staat de zin zonder die instructie; de instructie zelf
--    staat in opmerking, zodat ze niet verloren gaat.
--
-- 2. De samengestelde codes (H350i, H360F, H360D, H360FD, H360Fd, H360Df,
--    H360fD, H361f, H361d, H361fd) staan NIET als aparte regel in bijlage III.
--    Ze ontstaan in bijlage VI door de openstaande plaats in te vullen. Ze staan
--    hier wel, want ze staan op echte bladen -- de chroomhoudende primer in de
--    demo draagt H350i. Hun tekst is afgeleid van de CLP-basiszin, zodat de hele
--    familie dezelfde woorden gebruikt, en hun bron zegt dat ook.
--
-- 3. De gecombineerde aanduidingen (H302+H312, H300+H310+H330 ...) staan hier
--    met opzet niet. Ze zijn niets meer dan twee of drie bestaande zinnen achter
--    elkaar, en het portaal splitst zo'n code zelf op de plustekens en plakt de
--    zinnen aan elkaar. Zo werkt elke combinatie, ook die welke niemand
--    vooraf bedacht heeft.
--
-- EUH001 en EUH059 zijn geschrapt uit CLP. Ze staan er toch bij, met die
-- vermelding in opmerking, omdat ze nog op oudere bladen circuleren en een
-- klant die er een tegenkomt beter leest dat de code vervallen is dan dat wij
-- hem niet kennen.
--
-- Wat NIET verandert: valt_onder_titel2() blijft beslissen welk product onder
-- titel 2 valt. De vlag titel2 hieronder dient om het in een scherm te tonen.
-- Die verdubbeling is bewust en staat uitgelegd in 0098.
-- ---------------------------------------------------------------------------

alter table gevaarzinnen add column if not exists bron text;
alter table gevaarzinnen add column if not exists opmerking text;

comment on column gevaarzinnen.bron is
  'Waar deze tekst vandaan komt. Ingevuld zodat de herkomst navraagbaar blijft.';
comment on column gevaarzinnen.opmerking is
  'Uitleg bij de code: een instructie aan de leverancier, of de melding dat de code geschrapt is.';

insert into gevaarzinnen (code, tekst, titel2, volgorde, bron, opmerking) values
  ('H200', 'Instabiele ontplofbare stof.', false, 100, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H201', 'Ontplofbare stof; gevaar voor massa-explosie.', false, 110, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H202', 'Ontplofbare stof, ernstig gevaar voor scherfwerking.', false, 120, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H203', 'Ontplofbare stof; gevaar voor brand, luchtdrukwerking of scherfwerking.', false, 130, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H204', 'Gevaar voor brand of scherfwerking.', false, 140, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H205', 'Gevaar voor massa-explosie bij brand.', false, 150, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H206', 'Gevaar voor brand, luchtdrukwerking of scherfwerking; toegenomen ontploffingsgevaar als de ongevoeligheidsagens wordt verminderd.', false, 160, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H207', 'Gevaar voor brand of scherfwerking; toegenomen ontploffingsgevaar als de ongevoeligheidsagens wordt verminderd.', false, 170, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H208', 'Gevaar voor brand; toegenomen ontploffingsgevaar als de ongevoeligheidsagens wordt verminderd.', false, 180, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H220', 'Zeer licht ontvlambaar gas.', false, 190, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H221', 'Ontvlambaar gas.', false, 200, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H222', 'Zeer licht ontvlambare aerosol.', false, 210, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H223', 'Ontvlambare aerosol.', false, 220, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H224', 'Zeer licht ontvlambare vloeistof en damp.', false, 230, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H225', 'Licht ontvlambare vloeistof en damp.', false, 240, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H226', 'Ontvlambare vloeistof en damp.', false, 250, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H228', 'Ontvlambare vaste stof.', false, 260, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H229', 'Houder onder druk: kan openbarsten bij verhitting.', false, 270, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H230', 'Kan explosief reageren zelfs in afwezigheid van lucht.', false, 280, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H231', 'Kan explosief reageren zelfs in afwezigheid van lucht bij verhoogde druk en/of temperatuur.', false, 290, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H232', 'Kan spontaan ontbranden bij blootstelling aan lucht.', false, 300, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H240', 'Ontploffingsgevaar bij verwarming.', false, 310, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H241', 'Brand- of ontploffingsgevaar bij verwarming.', false, 320, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H242', 'Brandgevaar bij verwarming.', false, 330, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H250', 'Vat spontaan vlam bij blootstelling aan lucht.', false, 340, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H251', 'Vatbaar voor zelfverhitting: kan vlam vatten.', false, 350, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H252', 'In grote hoeveelheden vatbaar voor zelfverhitting; kan vlam vatten.', false, 360, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H260', 'In contact met water komen ontvlambare gassen vrij die spontaan kunnen ontbranden.', false, 370, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H261', 'In contact met water komen ontvlambare gassen vrij.', false, 380, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H270', 'Kan brand veroorzaken of bevorderen; oxiderend.', false, 390, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H271', 'Kan brand of ontploffingen veroorzaken; sterk oxiderend.', false, 400, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H272', 'Kan brand bevorderen; oxiderend.', false, 410, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H280', 'Bevat gas onder druk; kan ontploffen bij verwarming.', false, 420, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H281', 'Bevat sterk gekoeld gas; kan cryogene brandwonden of letsel veroorzaken.', false, 430, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H290', 'Kan bijtend zijn voor metalen.', false, 440, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H300', 'Dodelijk bij inslikken.', false, 450, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H301', 'Giftig bij inslikken.', false, 460, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H302', 'Schadelijk bij inslikken.', false, 470, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H304', 'Kan dodelijk zijn als de stof bij inslikken in de luchtwegen terechtkomt.', false, 480, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H310', 'Dodelijk bij contact met de huid.', false, 490, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H311', 'Giftig bij contact met de huid.', false, 500, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H312', 'Schadelijk bij contact met de huid.', false, 510, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H314', 'Veroorzaakt ernstige brandwonden en oogletsel.', false, 520, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H315', 'Veroorzaakt huidirritatie.', false, 530, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H317', 'Kan een allergische huidreactie veroorzaken.', false, 540, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H318', 'Veroorzaakt ernstig oogletsel.', false, 550, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H319', 'Veroorzaakt ernstige oogirritatie.', false, 560, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H330', 'Dodelijk bij inademing.', false, 570, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H331', 'Giftig bij inademing.', false, 580, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H332', 'Schadelijk bij inademing.', false, 590, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H334', 'Kan bij inademing allergie- of astmasymptomen of ademhalingsmoeilijkheden veroorzaken.', false, 600, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H335', 'Kan irritatie van de luchtwegen veroorzaken.', false, 610, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H336', 'Kan slaperigheid of duizeligheid veroorzaken.', false, 620, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H340', 'Kan genetische schade veroorzaken.', true, 630, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', 'Op het etiket vult de leverancier hier de blootstellingsroute, het specifieke effect of het betrokken orgaan in.'),
  ('H341', 'Verdacht van het veroorzaken van genetische schade.', false, 640, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', 'Op het etiket vult de leverancier hier de blootstellingsroute, het specifieke effect of het betrokken orgaan in.'),
  ('H350', 'Kan kanker veroorzaken.', true, 650, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', 'Op het etiket vult de leverancier hier de blootstellingsroute, het specifieke effect of het betrokken orgaan in.'),
  ('H350i', 'Kan kanker veroorzaken bij inademing.', true, 660, 'CLP bijlage III, samengestelde code volgens bijlage VI', null),
  ('H351', 'Verdacht van het veroorzaken van kanker.', false, 670, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', 'Op het etiket vult de leverancier hier de blootstellingsroute, het specifieke effect of het betrokken orgaan in.'),
  ('H360', 'Kan de vruchtbaarheid of het ongeboren kind schaden.', true, 680, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', 'Op het etiket vult de leverancier hier de blootstellingsroute, het specifieke effect of het betrokken orgaan in.'),
  ('H360F', 'Kan de vruchtbaarheid schaden.', true, 690, 'CLP bijlage III, samengestelde code volgens bijlage VI', null),
  ('H360D', 'Kan het ongeboren kind schaden.', true, 700, 'CLP bijlage III, samengestelde code volgens bijlage VI', null),
  ('H360FD', 'Kan de vruchtbaarheid schaden. Kan het ongeboren kind schaden.', true, 710, 'CLP bijlage III, samengestelde code volgens bijlage VI', null),
  ('H360Fd', 'Kan de vruchtbaarheid schaden. Kan mogelijks het ongeboren kind schaden.', true, 720, 'CLP bijlage III, samengestelde code volgens bijlage VI', null),
  ('H360Df', 'Kan het ongeboren kind schaden. Kan mogelijks de vruchtbaarheid schaden.', true, 730, 'CLP bijlage III, samengestelde code volgens bijlage VI', null),
  ('H360fD', 'Kan het ongeboren kind schaden. Kan mogelijks de vruchtbaarheid schaden.', true, 740, 'CLP bijlage III, samengestelde code volgens bijlage VI', null),
  ('H361', 'Kan mogelijks de vruchtbaarheid of het ongeboren kind schaden.', false, 750, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', 'Op het etiket vult de leverancier hier de blootstellingsroute, het specifieke effect of het betrokken orgaan in.'),
  ('H361f', 'Kan mogelijks de vruchtbaarheid schaden.', false, 760, 'CLP bijlage III, samengestelde code volgens bijlage VI', null),
  ('H361d', 'Kan mogelijks het ongeboren kind schaden.', false, 770, 'CLP bijlage III, samengestelde code volgens bijlage VI', null),
  ('H361fd', 'Kan mogelijks de vruchtbaarheid schaden. Kan mogelijks het ongeboren kind schaden.', false, 780, 'CLP bijlage III, samengestelde code volgens bijlage VI', null),
  ('H362', 'Kan schadelijk zijn via de borstvoeding.', false, 790, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H370', 'Veroorzaakt schade aan organen.', false, 800, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', 'Op het etiket vult de leverancier hier de blootstellingsroute, het specifieke effect of het betrokken orgaan in.'),
  ('H371', 'Kan schade aan organen veroorzaken.', false, 810, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', 'Op het etiket vult de leverancier hier de blootstellingsroute, het specifieke effect of het betrokken orgaan in.'),
  ('H372', 'Veroorzaakt schade aan organen bij langdurige of herhaalde blootstelling.', false, 820, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', 'Op het etiket vult de leverancier hier de blootstellingsroute, het specifieke effect of het betrokken orgaan in.'),
  ('H373', 'Kan schade aan organen veroorzaken bij langdurige of herhaalde blootstelling.', false, 830, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', 'Op het etiket vult de leverancier hier de blootstellingsroute, het specifieke effect of het betrokken orgaan in.'),
  ('EUH380', 'Kan hormoonontregeling bij de mens veroorzaken.', true, 840, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH381', 'Wordt ervan verdacht hormoonontregeling bij de mens te veroorzaken.', true, 850, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H400', 'Zeer giftig voor in het water levende organismen.', false, 860, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H410', 'Zeer giftig voor in het water levende organismen, met langdurige gevolgen.', false, 870, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H411', 'Giftig voor in het water levende organismen, met langdurige gevolgen.', false, 880, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H412', 'Schadelijk voor in het water levende organismen, met langdurige gevolgen.', false, 890, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H413', 'Kan langdurige schadelijke gevolgen voor in het water levende organismen hebben.', false, 900, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('H420', 'Schadelijk voor de volksgezondheid en het milieu door afbraak van ozon in de bovenste lagen van de atmosfeer.', false, 910, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH430', 'Kan hormoonontregeling in het milieu veroorzaken.', false, 920, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH431', 'Wordt ervan verdacht hormoonontregeling in het milieu te veroorzaken.', false, 930, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH440', 'Accumulatie in het milieu en levende organismen, met inbegrip van mensen.', false, 940, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH441', 'Sterke accumulatie in het milieu en levende organismen, met inbegrip van mensen.', false, 950, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH450', 'Kan langdurige en diffuse verontreiniging van watervoorraden veroorzaken.', false, 960, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH451', 'Kan zeer langdurige en diffuse verontreiniging van watervoorraden veroorzaken.', false, 970, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH014', 'Reageert heftig met water.', false, 980, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH018', 'Kan bij gebruik een ontvlambaar/ontplofbaar damp-luchtmengsel vormen.', false, 990, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH019', 'Kan ontplofbare peroxiden vormen.', false, 1000, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH044', 'Ontploffingsgevaar bij verwarming in afgesloten toestand.', false, 1010, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH029', 'Vormt giftig gas in contact met water.', false, 1020, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH031', 'Vormt giftig gas in contact met zuren.', false, 1030, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH032', 'Vormt zeer giftig gas in contact met zuren.', false, 1040, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH066', 'Herhaalde blootstelling kan een droge of een gebarsten huid veroorzaken.', false, 1050, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH070', 'Giftig bij oogcontact.', false, 1060, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH071', 'Bijtend voor de luchtwegen.', false, 1070, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH201', 'Bevat lood. Mag niet worden gebruikt voor voorwerpen waarin kinderen kunnen bijten of waaraan kinderen kunnen zuigen.', false, 1080, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH201A', 'Let op! Bevat lood.', false, 1090, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', 'Verkorte vorm van EUH201, voor kleine verpakkingen.'),
  ('EUH209', 'Kan bij gebruik licht ontvlambaar worden.', false, 1100, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH209A', 'Kan bij gebruik ontvlambaar worden.', false, 1110, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH202', 'Cyanoacrylaat. Gevaarlijk. Kleeft binnen enkele seconden aan huid en oogleden. Buiten het bereik van kinderen houden.', false, 1120, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH203', 'Bevat zeswaardig chroom. Kan een allergische reactie veroorzaken.', false, 1130, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH204', 'Bevat isocyanaten. Kan een allergische reactie veroorzaken.', false, 1140, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH205', 'Bevat epoxyverbindingen. Kan een allergische reactie veroorzaken.', false, 1150, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH206', 'Let op! Niet in combinatie met andere producten gebruiken. Er kunnen gevaarlijke gassen (chloor) vrijkomen.', false, 1160, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH207', 'Let op! Bevat cadmium. Bij het gebruik ontwikkelen zich gevaarlijke dampen. Zie de aanwijzingen van de fabrikant. Neem de veiligheidsvoorschriften in acht.', false, 1170, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH208', 'Bevat [naam van de sensibiliserende stof]. Kan een allergische reactie veroorzaken.', false, 1180, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH210', 'Veiligheidsinformatieblad op verzoek verkrijgbaar.', false, 1190, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH211', 'Let op! Bij verneveling kunnen gevaarlijke inhaleerbare druppels worden gevormd. Spuitnevel niet inademen.', false, 1200, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH212', 'Let op! Bij gebruik kunnen gevaarlijke inhaleerbare stofdeeltjes worden gevormd. Stof niet inademen.', false, 1210, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH401', 'Volg de gebruiksaanwijzing om gevaar voor de menselijke gezondheid en het milieu te voorkomen.', false, 1220, 'CLP bijlage III, geconsolideerde tekst 01.02.2025', null),
  ('EUH001', 'In droge toestand ontplofbaar.', false, 1230, 'Vlaamse lijst gevarenaanduidingen 2015; geschrapt uit CLP', 'Geschrapt uit CLP. Komt nog voor op oudere bladen.'),
  ('EUH059', 'Gevaarlijk voor de ozonlaag.', false, 1240, 'Vlaamse lijst gevarenaanduidingen 2015; geschrapt uit CLP', 'Geschrapt uit CLP en vervangen door H420. Komt nog voor op oudere bladen.')

on conflict (code) do update set
  tekst     = excluded.tekst,
  titel2    = excluded.titel2,
  volgorde  = excluded.volgorde,
  bron      = excluded.bron,
  opmerking = excluded.opmerking,
  actief    = true;


-- ---------------------------------------------------------------------------
-- Controle
-- ---------------------------------------------------------------------------
-- Draait alleen een melding uit; verandert niets. Handig om na het uitvoeren te
-- zien dat de lijst staat waar je hem verwacht.
do $$
declare
  v_totaal int;
  v_titel2 int;
  v_zonder int;
begin
  select count(*) into v_totaal from gevaarzinnen where actief;
  select count(*) into v_titel2 from gevaarzinnen where actief and titel2;
  select count(*) into v_zonder from gevaarzinnen where actief and (bron is null or bron = '');
  raise notice 'Codelijst: % aanduidingen, waarvan % onder titel 2. Zonder bron: %.',
    v_totaal, v_titel2, v_zonder;
end
$$;

notify pgrst, 'reload schema';


-- ---------------------------------------------------------------------------
-- De tekst bij een code opzoeken
-- ---------------------------------------------------------------------------
-- Twee dingen die een rechtstreekse join op code niet aankan.
--
-- Ten eerste de gecombineerde aanduidingen: H302+H312 staat niet in de lijst en
-- hoeft er niet in. Ze is de twee losse zinnen achter elkaar. Zo werkt elke
-- combinatie, ook eentje die wij nooit gezien hebben.
--
-- Ten tweede de hoofdletters. De oude opzoeking in 0098 deed upper(code), en
-- dat brak precies op de codes waar het om draait: H350i werd H350I en vond
-- niets. Daarom eerst exact zoeken.
--
-- De terugval op hoofdletterongevoelig zoeken gebeurt alleen wanneer er precies
-- één kandidaat is. H360Fd en H360fD schelen enkel in hoofdletters en betekenen
-- iets anders -- de eerste is "kan de vruchtbaarheid schaden", de tweede
-- "kan mogelijks de vruchtbaarheid schaden". Daar mag niet geraden worden.
create or replace function public.gevaarzin_deel(p_code text)
returns text
language sql
stable
set search_path = public
as $$
  select coalesce(
    (select tekst from gevaarzinnen where code = p_code and actief),
    (select max(tekst) from gevaarzinnen
      where upper(code) = upper(p_code) and actief
      having count(*) = 1)
  );
$$;

-- Geeft null zodra één deel onbekend is. De app toont dan gewoon de code, en
-- dat is de bedoeling: een code zonder tekst is nog altijd een waarschuwing,
-- een weggelaten code niet.
create or replace function public.gevaarzin_tekst(p_code text)
returns text
language sql
stable
set search_path = public
as $$
  select case when bool_or(t is null) then null
              else string_agg(t, ' ' order by ord) end
  from (
    select ord, public.gevaarzin_deel(btrim(d)) as t
    from unnest(string_to_array(p_code, '+')) with ordinality as u(d, ord)
  ) x;
$$;

grant execute on function public.gevaarzin_deel(text)  to anon, authenticated;
grant execute on function public.gevaarzin_tekst(text) to anon, authenticated;


-- ---------------------------------------------------------------------------
-- rpc_chemie_product: dezelfde functie als in 0098, met die opzoeking erin
-- ---------------------------------------------------------------------------
-- Alleen het blok 'gevaren' verandert. De rest staat er ongewijzigd, want een
-- create or replace vervangt de hele functie.
create or replace function public.rpc_chemie_product(p_gebruiker_id uuid, p_product_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_bedrijf uuid;
  v_p record;
begin
  select bedrijf_id into v_bedrijf
  from gebruikers where id = p_gebruiker_id and actief = true;
  if v_bedrijf is null then
    raise exception 'Onbekende of inactieve gebruiker';
  end if;

  select * into v_p from chemische_producten
  where id = p_product_id and bedrijf_id = v_bedrijf and actief;
  if not found then
    raise exception 'Onbekend product';
  end if;

  return jsonb_build_object(
    'id', v_p.id,
    'naam', v_p.naam,
    'leverancier', v_p.leverancier,
    'toepassing', v_p.toepassing,
    'locatie', v_p.locatie,
    'hoeveelheid', v_p.hoeveelheid,
    'pictogrammen', to_jsonb(v_p.pictogrammen),
    'onder_titel2', v_p.onder_titel2,
    'vib_url', v_p.vib_url,
    'vib_datum', v_p.vib_datum,
    'opmerking', v_p.opmerking,
    -- Een code waarvan de tekst niet gevonden wordt, blijft als code staan.
    -- Weglaten zou erger zijn: dan toont de app een product als ongevaarlijk
    -- omdat wij een zin missen.
    'gevaren', coalesce((
      select jsonb_agg(jsonb_build_object(
               'code',   t.code,
               'tekst',  public.gevaarzin_tekst(t.code),
               'titel2', public.valt_onder_titel2(array[t.code]))
             order by t.code)
      from unnest(v_p.h_zinnen) as t(code)
    ), '[]'::jsonb)
  );
end;
$$;

grant execute on function public.rpc_chemie_product(uuid, uuid) to anon, authenticated;

notify pgrst, 'reload schema';
