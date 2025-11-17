export interface FieldValue {
  fromString(value: string): boolean
  toString(): string
}