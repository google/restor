/// Copyright 2017 Google Inc. All rights reserved.
///
/// Licensed under the Apache License, Version 2.0 (the "License");
/// you may not use this file except in compliance with the License.
/// You may obtain a copy of the License at
///
///    http://www.apache.org/licenses/LICENSE-2.0
///
///    Unless required by applicable law or agreed to in writing, software
///    distributed under the License is distributed on an "AS IS" BASIS,
///    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
///    See the License for the specific language governing permissions and
///    limitations under the License.

#import "Restor/Views/ImageNamedValueTransformer.h"

@implementation ImageNamedValueTransformer

+ (Class)transformedValueClass {
  return [NSImage class];
}

+ (BOOL)allowsReverseTransformation {
  return NO;
}

- (id)transformedValue:(id)value {
  if (!value) return nil;
  if (![value isKindOfClass:[NSString class]]) {
    @throw [NSException exceptionWithName:@"ImageNamedValueTransformerInvalidInput"
                                   reason:@"ImageNamedValueTransformer only transforms strings"
                                 userInfo:nil];
  }
  return [NSImage imageNamed:value];
}

@end
