export interface Profile {
  userId: string;
  displayName: string | null;
  avatarUrl: string | null;
  about: string | null;
}

export interface ProfileRepository {
  get(userId: string): Promise<Profile>;
  upsert(userId: string, input: { displayName?: string | null; avatarUrl?: string | null; about?: string | null }): Promise<Profile>;
}
