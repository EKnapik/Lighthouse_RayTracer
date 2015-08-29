// Author: Eric M. Knapik



struct SpotLight {
    vec3 pos;
    vec3 dir;
    vec3 color;
    float intensity;
    float spread;
    float penFactor;
};

// If I can figure out the trochoid waves that would make this nicer
float wave(vec3 p, float speed, float amp, float angle, float freq) {
    return amp*cos(freq*(freq*(p.x*cos(angle) + p.z*sin(angle)) - speed*iGlobalTime) - speed*iGlobalTime);
}

float fbm(vec2 p) {
    float ql = length( p );
    p.x += 0.05*sin(.81*iGlobalTime+ql*2.0);
    p.y += 0.05*sin(1.53*iGlobalTime+ql*6.0);
    
    float total = 0.0;
    float freq = 0.0152250;
    float lacunarity = 2.51;
    float gain = 0.15;
    float amp = gain;
    
    for(int i = 0; i < 5; i++) {
        total += texture2D(iChannel0, p*freq).r*amp;
        freq *= lacunarity;
        amp *= gain;
    }
    
    return total;
}


//----------DISTNACE FUNCTIONS----------
float distSphere(vec3 pos, float r) {
    return length(pos)-r;
}

float distOcean(vec3 pos) {
    return pos.y + fbm(pos.xz + .5*fbm(pos.xz + fbm(pos.xz))) + wave(pos, .3, .0413, .23, 2.0) + wave(pos, .15, .12, -.35, .5);
}

float distMoon(vec3 pos) {
    float radius = 2.0;
    vec3 desiredPos = vec3(-30.0,5.0,-30.0);
    return length(pos-desiredPos)-radius;
}
//---------END DISTANCE FUNCTIONS--------


//-----------OBJECT OPERATIONS-----------
// need to write my own min function
vec2 shapeMin(vec2 shape1, vec2 shape2) {
    return (shape1.x < shape2.x) ? shape1 : shape2;
}
//----------END OBJECT OPERATIONS----------


//-----------OBJ MAP AND RAYMARCH-------------
vec2 map(vec3 pos) {
    vec2 shape; // the distance to this shape and the shape id
                // distance to shape is x, shape id is y
    shape = shapeMin(vec2(distOcean(pos), 1.0), vec2(distSphere(pos-vec3(0.0, 0.0, 0.0), 0.5), 2.0));
    shape = shapeMin(shape,                     vec2(distMoon(pos), 3.0));
    return shape;
}

vec2 rayMarch(in vec3 rayOrigin, in vec3 rayDir) {
    float tmin = 0.0;
    float tmax = 60.0;
    
    float t = tmin;
    float precis = 0.002;
    float material = -1.0;
    
    // for more accuracy increase the amount of checks in the for loop
    for(int i = 0; i < 60; i++) {
        vec2 shapeObj = map(rayOrigin + t*rayDir);
        float dist = shapeObj.x;
        if(dist < precis || t > tmax) {
            break;
        }
        t += dist;
        material = shapeObj.y;
    }
    
    if( t>tmax ) {
        material = -1.0; // didn't hit anything so background;
    }
    return vec2( t, material ); // return distance and material hit for this ray
}


// ----- LIGHTING --------
// Inigo Quilez's soft shadow
float softshadow(vec3 rayOrigin, vec3 rayDir, float mint, float maxt) {
    float k = 8.0; // how soft the shadow is (a constant)
    float res = 1.0;
    float t = mint;
    for(int i=0; i<16; i++) {
        float h = map(rayOrigin + t*rayDir).x;
        res = min(res, k*h/t);
        t += h; // can clamp how much t increases by for more precision
        if( h < 0.001 ) {
            break;
        }
    }
    return clamp(res, 0.0, 1.0);
}

// Inigo Quilez's fast normal adjusted slightly cause I was shading myself
vec3 calcNormal(vec3 pos) {
    vec3 epsilon = vec3(0.023, 0.0, 0.0);
    vec3 nor = vec3(
        map(pos+epsilon.xyy).x - map(pos-epsilon.xyy).x,
        map(pos+epsilon.yxy).x - map(pos-epsilon.yxy).x,
        map(pos+epsilon.yyx).x - map(pos-epsilon.yyx).x);
    return normalize(nor);
}


// --- COMBINE EVERYTHING TO GET PIXEL COLOR
vec3 calColor(vec3 rayOrigin, vec3 rayDir) {
    vec3 matCol; // material color
    // finds the t of intersect and what is it intersected with
    vec2 result = rayMarch(rayOrigin, rayDir);
    float t = result.x;
    
    vec3 pos = rayOrigin + t*rayDir;
    vec3 nor = calcNormal( pos );
    vec3 reflectEye = normalize(reflect(normalize(-rayDir), nor)); // rayDir is the eye to position
    float specCoeff, diffCoeff, ambCoeff = 0.0;                    // dependant on material
    float shadow, spotCos, spotCoeff = 0.0;                        // how much in the light
    
    // DEFINE two spot lights'Moon' and one simulates the moonlight
    vec3  ligPos = vec3(-20.0,5.0,-20.0);
    // some interesting toon style shading if the light vector isnt normalized
    vec3 lig = normalize(ligPos-pos);
    
    // set the material coefficients
    if(result.y > 0.5 && result.y < 1.5) { //water
        matCol = vec3(0.20,0.35,0.55);
        float fo=pow(0.023*result.x, 1.1);
            matCol=mix(matCol,vec3(0.91,0.88,0.98),fo);
    } else if(result.y > 1.5 && result.y < 2.5) { //sphere in water
        matCol = vec3(0.8);
    } else if(result.y > 2.5 && result.y < 3.5) { //moon
        matCol = vec3(0.5);
    } else {
        return matCol = vec3(0.2, 0.4, 0.75);
    }
    specCoeff = 1.20;
    diffCoeff = 1.20;
    ambCoeff = 0.10;
    
    // calculate light addition per spotlight
    // Bidirectional reflectance distribution function
    float dif = clamp( dot( nor, lig ), 0.0, 1.0 );
    float spe = pow(clamp( dot( reflectEye, lig ), 0.0, 1.0 ),16.0);
        
    dif *= softshadow( pos, lig, 0.025, 2.5 );

    vec3 brdf = vec3(0.0);
    brdf += diffCoeff*dif*vec3(1.00,1.0,1.0);
    brdf += specCoeff*spe*vec3(1.00,0.90,0.60)*dif;
    brdf += ambCoeff*vec3(0.50,0.70,1.00);

    brdf += 0.02;
    matCol = matCol*brdf;
    
    return vec3(clamp(matCol, 0.0, 1.0));  
}



// CAMERA SETTING
mat3 mkCamMat(in vec3 rayOrigin, in vec3 lookAtPoint, float roll) {
    vec3 cw = normalize(lookAtPoint - rayOrigin);
    vec3 cp = vec3(sin(roll), cos(roll), 0.0); //this is a temp right vec for cross determination
    vec3 cu = normalize(cross(cw, cp));
    vec3 cv = normalize(cross(cu, cw));

    return mat3(cu, cv, cw);
}


void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    vec2 q = fragCoord.xy / iResolution.xy;
    vec2 p = -1.0 + 2.0*q;
    p.x *= iResolution.x / iResolution.y;
    
    // camera or eye (where rays start)
    vec3 rayOrigin = vec3(0.0, 1.5, 4.0);
    vec3 lookAtPoint = vec3(-1.0, 1.5, 0.0);
    float focalLen = 1.0; // how far camera is from image plane
    mat3 camMat = mkCamMat(rayOrigin, lookAtPoint, 0.0);

    // ray direction into image plane
    vec3 rayDir = camMat * normalize(vec3(p.xy, focalLen));
    
    //render the scene with ray marching
    vec3 col = calColor(rayOrigin, rayDir);

    fragColor = vec4(col, 1.0); 
    //fragColor = vec4(.9); // that off white
}

