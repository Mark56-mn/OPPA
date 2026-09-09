export interface Profile {
  userId: string;
  displayName: string | null;
  avatarUrl: string | null;
  about: string | null;
  oppaId?: string | null;
}

export interface ProfileRepository {
  get(userId: string): Promise<Profile>;
  upsert(userId: string, input: { displayName?: string | null; avatarUrl?: string | null; about?: string | null }): Promise<Profile>;
  /** True when the handle is valid-shaped and not claimed by another user. */
  isOppaIdAvailable?(id: string, exceptUserId: string): Promise<boolean>;
  /** Sets (or changes) the caller's OPPA ID. Server validates everything. */
  setOppaId?(userId: string, id: string): Promise<Profile>;
  /** Public lookup for Connect/discovery (no contact data). */
  findByOppaId?(id: string): Promise<{ userId: string; displayName: string | null; oppaId: string } | null>;
}
