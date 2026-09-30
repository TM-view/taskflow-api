import { Injectable } from '@nestjs/common';

@Injectable()
export class AppService {
  // SIMULATED BAD CHANGE: Hardcoded AWS secret key to demonstrate Gate Blocking
  private readonly awsSecretKey = 'AKIAIOSFODNN7EXAMPLEEXAMPLEKEY123456789';

  getHello(): string {
    return 'Hello World!';
  }
}
