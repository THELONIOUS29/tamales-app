import { createClient } from 'npm:@supabase/supabase-js@2';

// ORS_API_KEY stays exclusively in Supabase Secrets, never in the APK.
const headers = { 'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, apikey, content-type, x-client-info' };
const json = (data: unknown, status = 200) => Response.json(data, { status, headers });
Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers });
  if (req.method !== 'POST') return json({error:'method_not_allowed'},405);
  try {
    const authorization=req.headers.get('Authorization') ?? '';
    if(!authorization.startsWith('Bearer ')) return json({error:'unauthorized'},401);
    const db=createClient(Deno.env.get('SUPABASE_URL')!,Deno.env.get('SUPABASE_ANON_KEY')!,
      {global:{headers:{Authorization:authorization}},auth:{persistSession:false}});
    const {data:{user},error:authError}=await db.auth.getUser(authorization.slice(7));
    if(authError||!user)return json({error:'unauthorized'},401);
    const {data:owner,error:ownerError}=await db.rpc('device_owner');
    if(ownerError||!owner)return json({error:'device_not_authorized'},403);
    const raw=await req.text();
    if(raw.length>16000)return json({error:'request_too_large'},413);
    const {locations}=JSON.parse(raw);
    if(!Array.isArray(locations)||locations.length<2||locations.length>59||
      !locations.every((p:unknown)=>Array.isArray(p)&&p.length===2&&
        p.every((v:unknown)=>typeof v==='number'&&Number.isFinite(v))&&
        Math.abs(p[0])<=180&&Math.abs(p[1])<=90))return json({error:'invalid_locations'},400);
    const key=Deno.env.get('ORS_API_KEY');
    if(!key)return json({error:'routing_not_configured'},503);
    const {data:allowed,error:quotaError}=await db.rpc('reserve_route_request');
    if(quotaError)return json({error:'quota_unavailable'},503);
    if(!allowed)return json({error:'daily_limit'},429);
    const response=await fetch('https://api.heigit.org/openrouteservice/v2/matrix/driving-car',{
      method:'POST',headers:{Authorization:key,'Content-Type':'application/json'},
      body:JSON.stringify({locations,metrics:['duration','distance']}),signal:AbortSignal.timeout(25000)});
    if(!response.ok)return json({error:response.status===429 ? 'provider_limit' : 'provider_unavailable'},502);
    const data=await response.json();
    if(!data.durations||!data.distances)return json({error:'invalid_provider_response'},502);
    return json({durations:data.durations,distances:data.distances,
      attribution:'© openrouteservice.org by HeiGIT | Map data © OpenStreetMap contributors'});
  } catch {return json({error:'routing_unavailable'},503);}
});

