// Static model configuration - in production this could come from DynamoDB
const AVAILABLE_MODELS = [
  {
    modelId: 'stable-diffusion-xl',
    name: 'Stable Diffusion XL',
    description: 'High-quality text-to-image generation with excellent prompt following',
    category: 'text-to-image',
    version: '1.0',
    maxResolution: 1024,
    defaultSteps: 20,
    maxSteps: 50,
    supportedQualities: ['low', 'medium', 'high'],
    estimatedTime: {
      low: '10-15 seconds',
      medium: '15-25 seconds',
      high: '25-40 seconds'
    },
    pricing: {
      low: 0.02,
      medium: 0.03,
      high: 0.05
    },
    features: [
      'High resolution output',
      'Excellent prompt adherence',
      'Style flexibility',
      'Fast inference'
    ],
    limitations: [
      'English prompts work best',
      'May struggle with very complex scenes',
      'Limited to square/rectangular outputs'
    ]
  },
  {
    modelId: 'stable-diffusion-v2',
    name: 'Stable Diffusion v2.1',
    description: 'Reliable text-to-image generation with good quality and speed balance',
    category: 'text-to-image',
    version: '2.1',
    maxResolution: 768,
    defaultSteps: 20,
    maxSteps: 50,
    supportedQualities: ['low', 'medium', 'high'],
    estimatedTime: {
      low: '8-12 seconds',
      medium: '12-20 seconds',
      high: '20-30 seconds'
    },
    pricing: {
      low: 0.015,
      medium: 0.025,
      high: 0.04
    },
    features: [
      'Fast inference',
      'Good prompt following',
      'Stable results',
      'Lower cost'
    ],
    limitations: [
      'Lower maximum resolution',
      'Less detailed than XL version',
      'May require more specific prompts'
    ]
  }
];

// Get user ID from JWT token
function getUserId(event) {
  try {
    const claims = event.requestContext.authorizer.jwt.claims;
    return claims.sub || claims['cognito:username'] || 'anonymous';
  } catch (error) {
    console.warn('Could not extract user ID from token:', error);
    return 'anonymous';
  }
}

// Filter models based on user tier (could be extended for premium features)
function filterModelsForUser(models, userId) {
  // For now, all users get access to all models
  // In the future, this could check user subscription tier
  return models.map(model => ({
    ...model,
    available: true,
    reason: model.available === false ? 'Requires premium subscription' : null
  }));
}

exports.handler = async (event) => {
  console.log('Event:', JSON.stringify(event, null, 2));
  
  try {
    // Get user ID for potential filtering
    const userId = getUserId(event);
    
    // Parse query parameters
    const queryParams = event.queryStringParameters || {};
    const category = queryParams.category;
    const includeDetails = queryParams.details === 'true';
    
    // Filter models by category if specified
    let models = AVAILABLE_MODELS;
    if (category) {
      models = models.filter(model => model.category === category);
    }
    
    // Filter models based on user permissions
    models = filterModelsForUser(models, userId);
    
    // Prepare response based on detail level
    const response = {
      models: models.map(model => {
        const baseModel = {
          modelId: model.modelId,
          name: model.name,
          description: model.description,
          category: model.category,
          version: model.version,
          available: model.available
        };
        
        if (includeDetails) {
          return {
            ...baseModel,
            maxResolution: model.maxResolution,
            defaultSteps: model.defaultSteps,
            maxSteps: model.maxSteps,
            supportedQualities: model.supportedQualities,
            estimatedTime: model.estimatedTime,
            pricing: model.pricing,
            features: model.features,
            limitations: model.limitations
          };
        }
        
        return baseModel;
      }),
      categories: [...new Set(AVAILABLE_MODELS.map(m => m.category))],
      totalCount: models.length
    };
    
    // Add usage recommendations
    if (includeDetails) {
      response.recommendations = {
        beginners: 'stable-diffusion-v2',
        quality: 'stable-diffusion-xl',
        speed: 'stable-diffusion-v2',
        cost: 'stable-diffusion-v2'
      };
      
      response.qualityGuide = {
        low: 'Faster generation, lower quality, good for testing prompts',
        medium: 'Balanced speed and quality, recommended for most use cases',
        high: 'Best quality, slower generation, ideal for final images'
      };
    }
    
    return {
      statusCode: 200,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'OPTIONS,GET',
        'Cache-Control': 'public, max-age=300' // Cache for 5 minutes
      },
      body: JSON.stringify(response)
    };
    
  } catch (error) {
    console.error('Error:', error);
    
    return {
      statusCode: 500,
      headers: {
        'Content-Type': 'application/json',
        'Access-Control-Allow-Origin': '*',
        'Access-Control-Allow-Headers': 'Content-Type,X-Amz-Date,Authorization,X-Api-Key,X-Amz-Security-Token',
        'Access-Control-Allow-Methods': 'OPTIONS,GET'
      },
      body: JSON.stringify({
        error: 'Internal server error',
        details: error.message
      })
    };
  }
};