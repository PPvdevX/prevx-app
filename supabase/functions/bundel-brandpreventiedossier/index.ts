// Supabase Edge Function: bindt het brandpreventiedossier tot één PDF.
//
// ---------------------------------------------------------------------------
// Waarom dit een functie is en geen knop in de browser
// ---------------------------------------------------------------------------
// De bestaande knop opende een afdrukvenster met een overzicht: de elf
// onderdelen, de keuringen, en een tabel met titels van documenten. Nuttig als
// inhoudsopgave, maar het is niet wat er gevraagd wordt wanneer de brandweer
// aan de balie staat. Die wil het dossier, niet de lijst.
//
// PDF's samenvoegen kan een browser niet uit zichzelf. Het kan wel hier: de
// documenten staan in een privébucket (0070) die de service-rol rechtstreeks
// mag lezen, dus er hoeven geen ondertekende links langs de browser te gaan.
//
// ---------------------------------------------------------------------------
// Wie mag dit
// ---------------------------------------------------------------------------
// Anders dan verzend-nieuwsbrief is dit géén superbeheerder-functie: een klant
// hoort zijn eigen dossier te kunnen bundelen. Daarom wordt eerst met de
// sleutel van de aanroeper zelf opgevraagd welke documenten hij mag zien -- dat
// laat RLS het werk doen -- en pas daarna met de service-rol gedownload. Zo kan
// niemand het dossier van een ander bedrijf opvragen door een id te raden.
//
// Verify JWT hoort hier AAN te staan, net als bij verzend-nieuwsbrief.
//
// Deploy:
//   supabase functions deploy bundel-brandpreventiedossier

// @ts-nocheck
import { createClient } from 'npm:@supabase/supabase-js@2';
import { PDFDocument, StandardFonts, rgb } from 'npm:pdf-lib@1.17.1';

const SUPABASE_URL = Deno.env.get('SUPABASE_URL');
const SERVICE_ROLE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
const ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY');

const TOEGELATEN_HERKOMST = ['https://prevx.be', 'https://www.prevx.be'];

function corsHeaders(req) {
  const herkomst = req.headers.get('origin') || '';
  return {
    'Access-Control-Allow-Origin': TOEGELATEN_HERKOMST.includes(herkomst) ? herkomst : TOEGELATEN_HERKOMST[0],
    'Access-Control-Allow-Headers': 'authorization, content-type',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    // Zonder deze regel ziet JavaScript in de browser alleen content-type en
    // content-length. Eigen headers worden bij een cross-origin antwoord
    // standaard verborgen -- de aanroeper las dus null en meldde '? documenten
    // gebonden'.
    'Access-Control-Expose-Headers': 'X-Gebonden, X-Overgeslagen'
  };
}

// Vijftig megabyte aan bronmateriaal is al een fors dossier. Boven die grens
// stoppen we liever met een duidelijke melding dan dat de functie zonder uitleg
// op haar geheugenlimiet stukloopt.
const MAX_TOTAAL_BYTES = 50 * 1024 * 1024;

const NAVY = rgb(0, 0.2, 0.4);
const GRIJS = rgb(0.39, 0.45, 0.55);
const ZWART = rgb(0.06, 0.09, 0.16);

function bestandsnaamUit(url) {
  try {
    const p = decodeURIComponent(String(url).split('?')[0]);
    return p.substring(p.lastIndexOf('/') + 1);
  } catch (e) {
    return 'document';
  }
}

// De opslagverwijzing uit een bewaarde URL peuteren. Dezelfde vorm als
// priveVerwijzing() in het portaal; die twee horen gelijk te blijven.
function opslagPad(url) {
  const m = /\/storage\/v1\/object\/(?:public\/|sign\/)?([^\/?]+)\/([^?]+)/.exec(String(url || ''));
  if (!m) return null;
  return { bucket: m[1], pad: decodeURIComponent(m[2]) };
}

// De volgorde van de elf onderdelen zoals de codex ze opsomt (boek III, titel 3).
// Alfabetisch sorteren gaf BPR voor BRA en zette het evacuatieplan tussen de
// algemene stukken -- een stapel PDF's in plaats van een dossier. Wie dit aan de
// brandweer geeft, hoort het in de volgorde te krijgen waarin ernaar gevraagd
// wordt.
//
// Types die niet tot het dossier behoren (risicoanalyse, GPP, JAP, toolbox)
// komen erna, met hun eigen volgorde. Ze horen erbij als achtergrond, maar niet
// tussen de elf.
//
// Onderdeel 10 is ADB, niet ADV: ADV is de gewone adviesnota en die kan over om
// het even welk risico gaan. Ze blijft in de bundel, maar achteraan bij de
// achtergrond -- niet tussen de stukken die de brandweer opvraagt.
const DOSSIER_VOLGORDE = ['BRA', 'BBD', 'BPR', 'EVP', 'ITD', 'EVO', 'BMP', 'AFW', 'ADB', 'HLP'];
const NA_HET_DOSSIER = ['RIS', 'GPP', 'JAP', 'ADV', 'AUD', 'RPT', 'CHL', 'TBX', 'FOR', 'TPL'];

function rangschik(type) {
  const i = DOSSIER_VOLGORDE.indexOf(type);
  if (i >= 0) return i;
  const j = NA_HET_DOSSIER.indexOf(type);
  return 100 + (j >= 0 ? j : 50);
}

function isPdf(naam, type) {
  return /\.pdf$/i.test(naam) || String(type || '').indexOf('pdf') >= 0;
}
function isAfbeelding(naam) {
  return /\.(png|jpe?g)$/i.test(naam);
}

// ---------------------------------------------------------------------------
Deno.serve(async (req) => {
  try {
    return await verwerk(req);
  } catch (e) {
    console.error('bundel-brandpreventiedossier crashte:', e && e.stack ? e.stack : e);
    return new Response(JSON.stringify({ error: String((e && e.message) || e) }), {
      status: 500,
      headers: { 'Content-Type': 'application/json', ...corsHeaders(req) }
    });
  }
});

async function verwerk(req) {
  function fout(data, status) {
    return new Response(JSON.stringify(data), {
      status: status || 400,
      headers: { 'Content-Type': 'application/json', ...corsHeaders(req) }
    });
  }

  if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: corsHeaders(req) });
  if (req.method !== 'POST') return fout({ error: 'Gebruik POST' }, 405);

  const { bedrijf_id } = await req.json().catch(() => ({}));
  if (!bedrijf_id) return fout({ error: 'bedrijf_id ontbreekt' }, 400);

  // Stap 1: met de sleutel van de aanroeper opvragen wat hij mag zien. Geeft
  // RLS niets terug, dan hoort hij niet bij dit bedrijf en stopt het hier.
  const auth = req.headers.get('Authorization') || '';
  const alsGebruiker = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: auth } }
  });

  const { data: docs, error: dFout } = await alsGebruiker
    .from('documenten')
    .select('id,type,titel,versie,bestand_url,geupload_op,code')
    .eq('bedrijf_id', bedrijf_id)
    .order('type')
    .order('geupload_op', { ascending: false });

  if (dFout) {
    console.error('Documenten lezen faalde:', dFout);
    return fout({ error: 'Documenten konden niet gelezen worden' }, 500);
  }
  if (!docs || !docs.length) {
    return fout({ error: 'Geen documenten in dit dossier, of geen toegang tot dit bedrijf' }, 404);
  }

  // Op dossiervolgorde zetten. Binnen hetzelfde type blijft de nieuwste bovenaan,
  // zoals de query ze al gaf.
  docs.sort((a, b) => rangschik(a.type) - rangschik(b.type));

  const { data: bedrijf } = await alsGebruiker
    .from('bedrijven').select('naam').eq('id', bedrijf_id).maybeSingle();

  // Stap 2: downloaden met de service-rol. De bucket is privé sinds 0070; zo
  // hoeft er geen ondertekende link langs de browser te reizen.
  const sb = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  const bundel = await PDFDocument.create();
  bundel.setTitle('Brandpreventiedossier ' + ((bedrijf && bedrijf.naam) || ''));
  bundel.setProducer('PrevX');

  const gewoon = await bundel.embedFont(StandardFonts.Helvetica);
  const vet = await bundel.embedFont(StandardFonts.HelveticaBold);

  const meegebonden = [];
  const overgeslagen = [];
  let totaal = 0;

  for (const d of docs) {
    const ref = opslagPad(d.bestand_url);
    const naam = bestandsnaamUit(d.bestand_url);
    if (!ref) { overgeslagen.push({ titel: d.titel, reden: 'geen bestand' }); continue; }

    if (!isPdf(naam) && !isAfbeelding(naam)) {
      // Bewust niet stilzwijgend weglaten: wie denkt dat hij alles heeft, kijkt
      // niet na wat er ontbreekt.
      overgeslagen.push({ titel: d.titel, reden: naam.split('.').pop().toUpperCase() + ' kan niet gebonden worden' });
      continue;
    }

    const { data: blob, error: sFout } = await sb.storage.from(ref.bucket).download(ref.pad);
    if (sFout || !blob) {
      console.error('Download faalde:', ref.pad, sFout);
      overgeslagen.push({ titel: d.titel, reden: 'bestand niet gevonden' });
      continue;
    }

    const bytes = new Uint8Array(await blob.arrayBuffer());
    totaal += bytes.length;
    if (totaal > MAX_TOTAAL_BYTES) {
      overgeslagen.push({ titel: d.titel, reden: 'bundel te groot geworden' });
      break;
    }

    try {
      if (isPdf(naam)) {
        const bron = await PDFDocument.load(bytes, { ignoreEncryption: true });
        const paginas = await bundel.copyPages(bron, bron.getPageIndices());
        paginas.forEach((p) => bundel.addPage(p));
      } else {
        const img = /\.png$/i.test(naam) ? await bundel.embedPng(bytes) : await bundel.embedJpg(bytes);
        // A4 staand, met marge; de afbeelding schaalt mee zonder te vervormen.
        const pagina = bundel.addPage([595, 842]);
        const schaal = Math.min((595 - 80) / img.width, (842 - 80) / img.height, 1);
        pagina.drawImage(img, {
          x: (595 - img.width * schaal) / 2,
          y: (842 - img.height * schaal) / 2,
          width: img.width * schaal,
          height: img.height * schaal
        });
      }
      meegebonden.push(d);
    } catch (e) {
      console.error('Samenvoegen faalde voor', d.titel, e && e.message);
      overgeslagen.push({ titel: d.titel, reden: 'bestand kon niet gelezen worden' });
    }
  }

  // Stap 3: het voorblad, en dat komt vooraan te staan. Het wordt als laatste
  // gemaakt omdat het moet vertellen wat er uiteindelijk in de bundel zit.
  const voorblad = bundel.insertPage(0, [595, 842]);
  let y = 780;
  const schrijf = (tekst, opties) => {
    const o = opties || {};
    voorblad.drawText(String(tekst), {
      x: o.x || 55, y: y, size: o.size || 10,
      font: o.vet ? vet : gewoon, color: o.kleur || ZWART
    });
    y -= (o.na || 16);
  };

  schrijf('Brandpreventiedossier', { size: 20, vet: true, kleur: NAVY, na: 24 });
  schrijf((bedrijf && bedrijf.naam) || '', { size: 12, kleur: GRIJS, na: 12 });
  schrijf('Gebundeld op ' + new Date().toISOString().slice(0, 10).split('-').reverse().join('/'),
    { size: 10, kleur: GRIJS, na: 30 });

  schrijf('In deze bundel', { size: 12, vet: true, kleur: NAVY, na: 18 });
  if (meegebonden.length) {
    meegebonden.forEach((d, i) => {
      if (y < 90) return;
      const versie = d.versie ? ' (v' + d.versie + ')' : '';
      schrijf((i + 1) + '.  [' + d.type + ']  ' + String(d.titel).slice(0, 70) + versie, { size: 10, na: 15 });
    });
  } else {
    schrijf('Geen enkel document kon gebonden worden.', { size: 10, kleur: GRIJS, na: 15 });
  }

  if (overgeslagen.length) {
    y -= 14;
    schrijf('Apart af te drukken', { size: 12, vet: true, kleur: rgb(0.86, 0.15, 0.15), na: 8 });
    schrijf('Deze stukken horen bij het dossier maar konden niet mee gebonden worden.',
      { size: 9, kleur: GRIJS, na: 16 });
    overgeslagen.forEach((o) => {
      if (y < 70) return;
      schrijf('•  ' + String(o.titel).slice(0, 60) + ' — ' + o.reden, { size: 9, kleur: GRIJS, na: 13 });
    });
  }

  voorblad.drawText(
    'Ter beschikking te houden van het comite, de met het toezicht belaste ambtenaren en de openbare hulpdiensten.',
    { x: 55, y: 45, size: 8, font: gewoon, color: GRIJS }
  );

  const pdf = await bundel.save();
  const bestandsnaam = 'brandpreventiedossier-' +
    String((bedrijf && bedrijf.naam) || 'dossier').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '') +
    '.pdf';

  return new Response(pdf, {
    status: 200,
    headers: {
      'Content-Type': 'application/pdf',
      'Content-Disposition': 'attachment; filename="' + bestandsnaam + '"',
      'X-Gebonden': String(meegebonden.length),
      'X-Overgeslagen': String(overgeslagen.length),
      ...corsHeaders(req)
    }
  });
}
