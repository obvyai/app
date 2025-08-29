import { APIGatewayProxyEvent, APIGatewayProxyResult } from 'aws-lambda';
import { ModelInfo, ListModelsResponse, QualityLevel } from '../types/api';
import { successResponse, errorResponse, optionsResponse } from '../utils/response';
import { extractUserContext } from '../utils/auth';
import { createChildLogger } from '../utils/logger';

// Static model configuration - in production this could come from DynamoDB or external service
const AVAILABLE_MODELS: ModelInfo[] = [
  {
    modelId: 'stable-diffusion-xl',
    name: 'Stable Diffusion XL',
    description: 'High-quality text-to-image generation with excellent prompt following and fine details',
    category: 'text-to-image',
    version: '1.0',
    maxResolution: 1024,
    defaultSteps: 20,
    maxSteps: 50,
    supportedQualities: [QualityLevel.LOW, QualityLevel.MEDIUM, QualityLevel.HIGH],
    estimatedTime: {
      [QualityLevel.LOW]: '10-15 seconds',
      [QualityLevel.MEDIUM]: '15-25 seconds',
      [QualityLevel.HIGH]: '25-40 seconds'
    },
    pricing: {
      [QualityLevel.LOW]: 0.02,
      [QualityLevel.MEDIUM]: 0.03,
      [QualityLevel.HIGH]: 0.05
    },
    features: [
      'High resolution output up to 1024x1024',
      'Excellent prompt adherence and understanding',
      'Wide range of artistic styles',
      'Fast inference with GPU acceleration',
      'Support for negative prompts',
      'Seed-based reproducible generation'
    ],
    limitations: [
      'English prompts work best',
      'May struggle with very complex multi-object scenes',
      'Limited to square and rectangular outputs',
      'Cannot generate text reliably',
      'May have bias in generated content'
    ],
    available: true
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
    supportedQualities: [QualityLevel.LOW, QualityLevel.MEDIUM, QualityLevel.HIGH],
    estimatedTime: {
      [QualityLevel.LOW]: '8-12 seconds',
      [QualityLevel.MEDIUM]: '12-20 seconds',
      [QualityLevel.HIGH]: '20-30 seconds'
    },
    pricing: {
      [QualityLevel.LOW]: 0.015,
      [QualityLevel.MEDIUM]: 0.025,
      [QualityLevel.HIGH]: 0.04
    },
    features: [
      'Fast inference speed',
      'Good prompt following',
      'Stable and consistent results',
      'Lower cost per generation',
      'Support for various aspect ratios'
    ],
    limitations: [
      'Lower maximum resolution than XL',
      'Less detailed than newer models',
      'May require more specific prompts',
      'Limited fine detail generation'
    ],
    available: true
  }
];

function filterModelsForUser(models: ModelInfo[], userId: string, isAdmin: boolean): ModelInfo[] {
  // For now, all users get access to all models
  // In the future, this could check user subscription tier, usage limits, etc.
  return models.map(model => ({
    ...model,
    available: true,
    reason: model.available === false ? 'Requires premium subscription' : undefined
  }));
}

export const handler = async (event: APIGatewayProxyEvent): Promise<APIGatewayProxyResult> => {
  const requestId = event.requestContext.requestId;
  const logger = createChildLogger({ requestId, handler: 'list-models' });
  
  try {
    // Handle CORS preflight
    if (event.httpMethod === 'OPTIONS') {
      return optionsResponse();
    }
    
    logger.info({ method: event.httpMethod, path: event.path }, 'Processing list models request');
    
    // Extract user context
    const userContext = extractUserContext(event);
    
    // Parse query parameters
    const queryParams = event.queryStringParameters || {};
    const category = queryParams.category;
    const includeDetails = queryParams.details === 'true';
    
    logger.info({ 
      userId: userContext.userId,
      category,
      includeDetails 
    }, 'Listing models');
    
    // Filter models by category if specified
    let models = AVAILABLE_MODELS;
    if (category) {
      models = models.filter(model => model.category === category);
      logger.debug({ category, filteredCount: models.length }, 'Filtered models by category');
    }
    
    // Filter models based on user permissions
    models = filterModelsForUser(models, userContext.userId, userContext.isAdmin);
    
    // Prepare response based on detail level
    const response: ListModelsResponse = {
      models: models.map(model => {
        const baseModel = {
          modelId: model.modelId,
          name: model.name,
          description: model.description,
          category: model.category,
          version: model.version,
          available: model.available,
          reason: model.reason
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
    
    // Add usage recommendations and guides for detailed requests
    if (includeDetails) {
      response.recommendations = {
        beginners: 'stable-diffusion-v2',
        quality: 'stable-diffusion-xl',
        speed: 'stable-diffusion-v2',
        cost: 'stable-diffusion-v2'
      };
      
      response.qualityGuide = {
        [QualityLevel.LOW]: 'Faster generation with reduced quality. Good for testing prompts and quick iterations.',
        [QualityLevel.MEDIUM]: 'Balanced speed and quality. Recommended for most use cases and general purpose generation.',
        [QualityLevel.HIGH]: 'Best quality with slower generation. Ideal for final images and professional use.'
      };
    }
    
    logger.info({ 
      modelCount: response.models.length,
      categories: response.categories,
      includeDetails 
    }, 'Models listed successfully');
    
    // Add cache headers for model list (can be cached for 5 minutes)
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
    logger.error({ error: error.message, stack: error.stack }, 'List models handler error');
    return errorResponse(error, requestId);
  }
};