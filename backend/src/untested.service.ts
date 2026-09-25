import { Injectable } from '@nestjs/common';

@Injectable()
export class UntestedService {
  getCalculatedData(value: number): string {
    if (value > 100) {
      return 'Value is too high';
    } else if (value > 50) {
      return 'Value is medium';
    } else if (value > 0) {
      return 'Value is low';
    } else {
      return 'Value is negative or zero';
    }
  }

  processUserRole(role: string): boolean {
    switch (role) {
      case 'admin':
        return true;
      case 'user':
        return false;
      default:
        return false;
    }
  }
}