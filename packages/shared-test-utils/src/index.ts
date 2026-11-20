export const eventually = async (assertion: () => Promise<void> | void, attempts = 10, delayMs = 100): Promise<void> => {
  let lastError: unknown;
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    try { await assertion(); return; } catch (error) { lastError = error; await new Promise((resolve) => setTimeout(resolve, delayMs)); }
  }
  throw lastError;
};
