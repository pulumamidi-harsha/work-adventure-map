// Environment configuration for CloudFront URLs
type Environment = {
    hostPatterns: string[];
    cloudfrontUrl: string;
};

type EnvironmentConfig = {
    dev: Environment;
    staging: Environment;
    prod: Environment;
};

export const ENV_CONFIG = {
    // Environment detection based on hostname patterns
    environments: {
        dev: {
            // Add your dev hostname patterns here
            hostPatterns: ['localhost', 'dev', 'development'],
            cloudfrontUrl: 'https://doizkviqkzeyt.cloudfront.net'
        },
        staging: {
            // Add your staging hostname patterns here
            hostPatterns: ['staging', 'stage', 'test'],
            cloudfrontUrl: 'https://d3fmrqmvjnwn6m.cloudfront.net'
        },
        prod: {
            // Add your production hostname patterns here
            hostPatterns: ['prod', 'production', 'workadventu.re'],
            cloudfrontUrl: 'https://d1ygxnweks0xtq.cloudfront.net'
        }
    } as EnvironmentConfig,
    
    // Default environment if no pattern matches
    defaultEnvironment: 'dev' as keyof EnvironmentConfig
};

// Function to detect current environment and return appropriate CloudFront URL
export function getEnvironmentUrl(): string {
    const hostname = window.location.hostname.toLowerCase();
    
    // Check each environment pattern
    for (const [, config] of Object.entries(ENV_CONFIG.environments)) {
        if (config.hostPatterns.some(pattern => hostname.includes(pattern.toLowerCase()))) {
            return config.cloudfrontUrl;
        }
    }
    
    // Return default environment URL if no pattern matches
    const defaultEnv = ENV_CONFIG.environments[ENV_CONFIG.defaultEnvironment];
    return defaultEnv.cloudfrontUrl;
}

// Generate the full URL for the application
export function getApplicationUrl() {
    const baseUrl = getEnvironmentUrl();
    return baseUrl;
}